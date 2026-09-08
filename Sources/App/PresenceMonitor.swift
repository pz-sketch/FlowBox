@preconcurrency import AVFoundation
import AppKit
import CoreImage
import SharedCore
import Vision

/// 人脸看守决策日志:记录空闲判定、摄像头确认结果与锁屏决策,用于排查「无人却不锁」。
/// 输出到 /tmp/flowbox-presence-debug.log,可随时查看/删除。
func presenceDebugLog(_ message: String) {
    FlowLog.general.debug("\(message, privacy: .public)")
    let url = URL(fileURLWithPath: "/tmp/flowbox-presence-debug.log")
    let line = "\(Date()) \(message)\n"
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - 人脸在场看守(纯本地 Vision 检测,不联网、不存图、不识别身份)
//
// 省电省绿灯逻辑:平时摄像头关闭,只用 HID 空闲时间做第一层感应。
//   - 有键盘/鼠标输入 → 视为有人,直接刷新在场时间,不开摄像头。
//   - 空闲超过阈值(默认 60 秒) → 短暂打开摄像头(约 5 秒)做一次本地人脸确认:
//     有人 → 关摄像头,重新计时;无人 → 自动锁屏(走 SystemLocker)。
//   - 绿灯只在短暂确认的几秒内亮,平时不亮。
//   - 确认无人、即将锁屏时,会按设置把那一帧快照存到本地
//     (presence-cap 目录,排查误锁用;画面只留本机,不联网不识别身份)。
//   - 锁屏是单向动作:macOS 不允许 App 绕过密码/Touch ID 自动解锁,
//     因此「回来」后仍需本人输密码或 Touch ID(不播提示音)。
//   - 与录屏画中画共用一颗摄像头时(macOS 允许多会话共享),暂停自建会话,
//     视为有人在场,避免重复占用。

@MainActor
final class PresenceMonitor: NSObject {

    static let shared = PresenceMonitor()

    /// 看守状态(供菜单与设置页展示)
    enum WatchState: Equatable {
        case off
        case waitingPermission
        case denied
        case watching(facePresent: Bool)
        case enrolling
    }

    private(set) var state: WatchState = .off {
        didSet { if state != oldValue { onChange?() } }
    }
    /// 状态变化回调(设置页打开时刷新状态行)
    var onChange: (() -> Void)?

    var isMonitoring: Bool {
        if case .watching = state { return true }
        return false
    }

    /// 摄像头当前是否打开(绿灯是否亮)
    var isCameraOn: Bool { session != nil }

    /// 是否正在注册主人脸(锁保护的快照,供设置页等非隔离上下文读取;
    /// 与 state == .enrolling 同义,但不经过 MainActor 隔离)
    nonisolated var isEnrolling: Bool {
        confirmLock.lock()
        defer { confirmLock.unlock() }
        return enrollSamples != nil
    }

    private var session: AVCaptureSession?
    private var output: AVCaptureVideoDataOutput?
    private let captureQueue = DispatchQueue(label: "net.ai2048.flowbox.presence", qos: .utility)
    private let confirmLock = NSLock()
    /// 确认结果:nil=仍在确认; true=窗口内见过人脸(有人); false=窗口结束全无人(要锁)
    private nonisolated(unsafe) var confirmResult: Bool?
    /// 见到人脸那一帧的主人脸相似度(nil=陌生人锁未开或未注册,无需比对)
    private nonisolated(unsafe) var confirmOwnerScore: Double?
    /// 注册模式:采集中(nil=不在注册);后台采集线程追加,主线程收尾
    private nonisolated(unsafe) var enrollSamples: [[Float]]?
    /// 注册目标样本数(后台只读)
    private nonisolated(unsafe) var enrollTarget: Int = 8
    /// 注册是否已在收尾(防采够与超时两路同时触发 finishEnroll)
    private nonisolated(unsafe) var enrollFinishing = false
    /// 注册截止时间(后台只读,超时自动失败,避免摄像头常开)
    private nonisolated(unsafe) var enrollDeadline = Date.distantPast
    /// 注册完成回调(仅主线程读写)
    private var enrollCompletion: ((Bool) -> Void)?
    /// 注册进度回调(仅主线程读写)
    private var enrollProgressCallback: ((Int, Int) -> Void)?
    /// 摄像头刚启动头几帧还没曝光(全黑),跳过它们再做人脸检测
    private nonisolated(unsafe) var warmupFramesRemaining: Int = 6
    /// 确认窗口内最近一帧(曝光稳定后),锁屏时存作快照
    private nonisolated(unsafe) var latestFrame: CVPixelBuffer?
    private var timer: Timer?
    private var lastActivity = Date()
    private var confirmDeadline = Date.distantPast
    private var confirming = false
    private var graceUntil = Date.distantPast
    private var lastAutoLock = Date.distantPast
    private var wasAbsent = false
    /// 屏幕已锁定时看守彻底休眠:不开摄像头、不计时,解锁后才恢复
    private var screenLocked = false
    /// 单次摄像头确认的最长时长(秒),超时无结果视为无人
    private let confirmWindow: TimeInterval = 5

    private override init() {
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(sessionBecameActive),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(sessionResignedActive),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        // 锁屏/解锁:锁屏不算会话切换,须单独监听,否则锁屏后 tick 继续跑、60 秒后又开摄像头
        let dist = DistributedNotificationCenter.default()
        dist.addObserver(
            self,
            selector: #selector(screenDidLock),
            name: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        dist.addObserver(
            self,
            selector: #selector(screenDidUnlock),
            name: NSNotification.Name("com.apple.screenIsUnlocked"),
            object: nil
        )
    }

    // MARK: - 对外入口

    /// 按当前配置启停(启动时与设置变更后调用)
    func refresh() {
        let cfg = AppConfig.load().presence
        if cfg.enabled {
            start(grace: cfg.gracePeriod)
        } else {
            stop()
        }
    }

    func start(grace: Double = 15) {
        if case .watching = state { return }
        if state == .waitingPermission { return }
        if state == .enrolling { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            state = .waitingPermission
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        self.beginWatching(grace: AppConfig.load().presence.gracePeriod)
                    } else {
                        self.state = .denied
                        FlowLog.permission.info("人脸看守:摄像头授权被拒绝")
                    }
                }
            }
            return
        case .denied, .restricted:
            state = .denied
            FlowLog.permission.info("人脸看守:无摄像头权限,未启动")
            return
        case .authorized:
            break
        @unknown default:
            break
        }
        beginWatching(grace: grace)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        closeCamera()
        confirming = false
        wasAbsent = false
        cancelEnroll()
        if state != .off {
            state = .off
            FlowLog.general.info("人脸看守:已停止")
        }
    }

    // MARK: - 主人脸注册(纯本地,特征向量只存配置文件)

    /// 开始注册:打开摄像头采集多帧人脸特征取平均存为"主人"。
    /// 注册期间暂停空闲看守计时,完成后自动恢复。progress(已采,目标),completion(成功)。
    func startEnroll(progress: @escaping (Int, Int) -> Void, completion: @escaping (Bool) -> Void) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            completion(false)
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            completion(false)
            return
        }
        cancelEnroll(restart: false)
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .low
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        self.session = session
        self.output = output
        confirmLock.lock()
        enrollSamples = []
        enrollTarget = 8
        enrollFinishing = false
        enrollDeadline = Date().addingTimeInterval(20)
        // 注册接管摄像头:丢弃可能正在进行的空闲确认,避免两套结论打架
        confirming = false
        confirmResult = nil
        confirmOwnerScore = nil
        confirmLock.unlock()
        enrollProgressCallback = progress
        enrollCompletion = completion
        state = .enrolling
        progress(0, 8)
        let sess = session
        captureQueue.async { sess.startRunning() }
        FlowLog.general.info("人脸看守:开始注册主人脸")
        // 超时兜底:主线程轮询,超时仍没采够则失败收尾(摄像头不会常开)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            Task { @MainActor in
                guard self.state == .enrolling else { t.invalidate(); return }
                self.confirmLock.lock()
                let finishing = self.enrollFinishing
                let timedOut = Date() > self.enrollDeadline
                let count = self.enrollSamples?.count ?? 0
                if timedOut, !finishing { self.enrollFinishing = true }
                self.confirmLock.unlock()
                if finishing {
                    // 采集侧已触发收尾,本轮询只停表
                    t.invalidate()
                } else if timedOut {
                    t.invalidate()
                    self.finishEnroll(success: false)
                } else {
                    // 顺手推进度(采集回调在后台线程,不直接碰主线程回调)
                    self.enrollProgressCallback?(count, self.enrollTarget)
                }
            }
        }
    }

    /// 取消注册(用户关开关/重进/退出时调用);restart=true 时恢复空闲看守
    func cancelEnroll(restart: Bool = true) {
        confirmLock.lock()
        let enrolling = enrollSamples != nil
        enrollSamples = nil
        confirmLock.unlock()
        enrollCompletion = nil
        enrollProgressCallback = nil
        if enrolling {
            closeCamera()
            FlowLog.general.info("人脸看守:注册已取消")
            if restart, state == .enrolling {
                // 先离注册态,否则 refresh()->start() 会因 enrolling 直接返回
                state = .off
                refresh()
            }
        }
    }

    /// 注册收尾(主线程):样本取平均存配置,恢复看守
    private func finishEnroll(success: Bool) {
        confirmLock.lock()
        let samples = enrollSamples ?? []
        enrollSamples = nil
        confirmLock.unlock()
        let completion = enrollCompletion
        enrollCompletion = nil
        enrollProgressCallback = nil
        let mean = success ? Faceprint.average(samples) : nil
        if let mean {
            var cfg = AppConfig.load()
            cfg.presence.ownerFaceprint = mean
            cfg.write()
            presenceDebugLog("注册主人脸成功: \(samples.count) 帧,向量 \(mean.count) 维")
            FlowLog.general.info("人脸看守:主人脸注册成功")
        } else {
            presenceDebugLog("注册主人脸失败:有效样本 \(samples.count)")
            FlowLog.general.info("人脸看守:主人脸注册失败(没拍到足够清晰的人脸)")
        }
        closeCamera()
        // 先离注册态,否则 refresh()->start() 因 enrolling 直接返回,看守停住
        state = .off
        refresh()
        completion?(mean != nil)
    }

    /// 人类可读状态(设置页/菜单展示)
    func statusText() -> String {
        switch state {
        case .off:
            return L10n.tr("未启用", "Off")
        case .waitingPermission:
            return L10n.tr("等待摄像头授权…", "Waiting for camera access…")
        case .denied:
            return L10n.tr("⚠️ 无摄像头权限,请在系统设置中允许", "⚠️ No camera access — allow in System Settings")
        case .enrolling:
            return L10n.tr("📷 正在注册主人脸:请正脸看镜头,保持光线充足…", "📷 Enrolling owner face: look at the camera in good light…")
        case .watching(let face):
            if screenLocked {
                return L10n.tr("💤 已锁屏,看守休眠中", "💤 Screen locked, watch asleep")
            }
            let cfg = AppConfig.load().presence
            if confirming {
                return L10n.tr("👁 正在确认是否有人…", "👁 Confirming presence…")
            }
            if face {
                return L10n.tr("👁 看守中:有操作,摄像头关闭", "👁 Watching: active, camera off")
            }
            return L10n.tr(
                "👁 看守中:无操作满 \(Int(cfg.lockAfterSeconds)) 秒后会开摄像头检测,没看到人脸则锁屏",
                "👁 Watching: checks the camera after \(Int(cfg.lockAfterSeconds))s idle; locks if no face"
            )
        }
    }

    // MARK: - 看守(无摄像头常驻)

    private func beginWatching(grace: Double) {
        lastActivity = Date()
        graceUntil = Date().addingTimeInterval(grace)
        wasAbsent = false
        confirming = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        state = .watching(facePresent: true)
        FlowLog.general.info("人脸看守:已启动(宽限 \(Int(grace))s,空闲感应模式)")
    }

    private func tick() {
        guard case .watching = state else { return }
        let cfg = AppConfig.load()
        guard cfg.presence.enabled else {
            stop()
            return
        }
        // 锁屏期间彻底休眠:不开摄像头、不计时(锁屏后本就无需看守)
        if screenLocked { return }
        let now = Date()
        // 录屏接管摄像头期间视为有人在场
        if ScreenRecorder.shared.isRecording || ScreenRecorder.shared.isCountingDown {
            lastActivity = now
            return
        }
        guard now >= graceUntil else { return }
        // 正在确认:等结果或超时
        if confirming {
            confirmLock.lock()
            let result = confirmResult
            let frame = latestFrame
            confirmLock.unlock()
            if let seen = result {
                presenceDebugLog("确认出结果: seen=\(seen), 立即收尾")
                finishConfirm(seen: seen)
            } else if now >= confirmDeadline {
                // 窗口结束仍无人脸 → 无人,锁屏前存快照(曝光稳定后的帧,避免黑帧)
                presenceDebugLog("确认窗口超时仍无结果, 按无人处理 (致锁屏)")
                if let frame, AppConfig.load().presence.saveCaptureOnLock {
                    Self.saveCaptureSnapshot(frame)
                }
                finishConfirm(seen: false)
            }
            return
        }
        // 第一层:系统级 HID 空闲时间(键盘+鼠标),有输入即视为有人
        let idle = systemIdleSeconds()
        if idle < cfg.presence.lockAfterSeconds {
            // 把锚点更新到晚于当前的那个:最后一次输入时刻(now-idle)或最近一次确认有人
            let lastInput = now.addingTimeInterval(-idle)
            if lastInput > lastActivity { lastActivity = lastInput }
            if wasAbsent {
                wasAbsent = false
                state = .watching(facePresent: true)
                FlowLog.general.info("人脸看守:检测到输入,恢复在场")
            } else if case .watching(let face) = state, !face {
                state = .watching(facePresent: true)
            }
            return
        }
        // 无操作满 lockAfterSeconds:开始需要人脸确认;
        // 之后用 confirmAfterSeconds 作为「复查间隔」:确认人还在且仍无操作,每隔这么久再查一次
        let sinceSeen = now.timeIntervalSince(lastActivity)
        if sinceSeen >= cfg.presence.confirmAfterSeconds {
            presenceDebugLog("无操作 idle=\(Int(idle))s sinceSeen=\(Int(sinceSeen))s >= confirmAfter=\(Int(cfg.presence.confirmAfterSeconds))s → 开摄像头确认")
            if case .watching(let face) = state, face {
                wasAbsent = true
                state = .watching(facePresent: false)
            }
            beginConfirm()
        }
        // 距上次确认有人/输入还没到复查间隔:保持在场状态,不动摄像头
    }

    /// 系统级无输入时长(秒),失败时返回 0(视为有人,宁可不锁不错锁)
    private func systemIdleSeconds() -> TimeInterval {
        // kCGAnyInputEventType = ~0,覆盖键盘/鼠标/触控板全部输入
        let idle = CGEventSource.secondsSinceLastEventType(
            .hidSystemState,
            eventType: CGEventType(rawValue: UInt32.max)!
        )
        guard idle.isFinite, idle >= 0, idle < 1_000_000 else { return 0 }
        return idle
    }

    // MARK: - 短暂摄像头确认

    private func beginConfirm() {
        presenceDebugLog("beginConfirm: 打开摄像头确认")
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            // 无权限则按空闲直接锁(用户已在设置页看到 denied 提示)
            presenceDebugLog("beginConfirm: 无摄像头权限 → lockNow")
            lockNow()
            return
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            NSLog("[FlowBox] 人脸看守:未找到可用摄像头,按空闲锁屏")
            presenceDebugLog("beginConfirm: 找不到摄像头 → lockNow")
            lockNow()
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .low
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: captureQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        self.session = session
        self.output = output
        confirmLock.lock()
        confirmResult = nil
        confirmOwnerScore = nil
        warmupFramesRemaining = 6
        latestFrame = nil
        confirmLock.unlock()
        confirming = true
        confirmDeadline = Date().addingTimeInterval(confirmWindow)
        let sess = session
        captureQueue.async { sess.startRunning() }
        FlowLog.general.info("人脸看守:空闲确认,短暂打开摄像头")
    }

    private func finishConfirm(seen: Bool) {
        presenceDebugLog("finishConfirm: seen=\(seen)")
        confirmLock.lock()
        let ownerScore = confirmOwnerScore
        confirmLock.unlock()
        closeCamera()
        confirming = false
        if seen {
            // 陌生人锁:开着且已注册主人脸,但相似度不够 → 视为陌生人,直接锁
            let cfg = AppConfig.load().presence
            if cfg.strangerLockEnabled, cfg.ownerFaceprint != nil, let score = ownerScore {
                if score < cfg.ownerMatchThreshold {
                    presenceDebugLog("陌生人锁:相似度 \(String(format: "%.2f", score)) < 阈值 \(cfg.ownerMatchThreshold) → lockNow")
                    FlowLog.general.info("人脸看守:检测到非主人脸,锁屏")
                    lockNow(reason: "陌生人脸自动锁屏")
                    return
                }
                presenceDebugLog("陌生人锁:相似度 \(String(format: "%.2f", score)) ≥ 阈值,通过")
            }
            // 确认有人:重置锚点,再等一个周期才复查;这里不播提示音,
            // 避免「人一直在但一直没操作」的周期性复查每次叮一声
            lastActivity = Date()
            wasAbsent = false
            state = .watching(facePresent: true)
            FlowLog.general.info("人脸看守:确认有人,关闭摄像头(\(Int(AppConfig.load().presence.confirmAfterSeconds))s 后复查)")
        } else {
            lockNow()
        }
    }

    private func closeCamera() {
        if let s = session {
            let sess = s
            captureQueue.async { sess.stopRunning() }
        }
        session = nil
        output = nil
    }

    private func lockNow(reason: String = "人脸离开自动锁屏") {
        let now = Date()
        let cooldownRemaining = Int(30 - now.timeIntervalSince(lastAutoLock))
        presenceDebugLog("lockNow: 距上次锁屏 \(Int(now.timeIntervalSince(lastAutoLock)))s (冷却30s) → \(cooldownRemaining > 0 ? "冷却中,不锁" : "执行锁屏")")
        // 锁后冷却 30 秒,避免重复触发
        if now.timeIntervalSince(lastAutoLock) >= 30 {
            lastAutoLock = now
            SystemLocker.lock(reason: reason)
        }
        lastActivity = now
        confirming = false
        closeCamera()
    }

    // MARK: - 锁屏/解锁通知

    @objc private func screenDidLock() {
        // 锁屏后看守休眠:关摄像头、停确认、停计时,绿灯不再亮;
        // 注册中也被取消(陌生人锁屏后不能留着半截注册态)
        screenLocked = true
        confirming = false
        cancelEnroll(restart: false)
        if state == .enrolling { state = .off }
        closeCamera()
        FlowLog.general.info("人脸看守:已锁屏,休眠")
    }

    @objc private func screenDidUnlock() {
        // 解锁后恢复:刷新在场时间并给宽限,避免刚输完密码就被锁
        screenLocked = false
        guard case .watching = state else { return }
        lastActivity = Date()
        graceUntil = Date().addingTimeInterval(AppConfig.load().presence.gracePeriod)
        wasAbsent = false
        confirming = false
        closeCamera()
        state = .watching(facePresent: true)
        FlowLog.general.info("人脸看守:已解锁,恢复看守")
    }

    @objc private func sessionBecameActive() {
        // 切换用户回来(非锁屏路径,锁屏解锁走 screenDidUnlock):同样给宽限
        if screenLocked { return }
        guard case .watching = state else { return }
        lastActivity = Date()
        graceUntil = Date().addingTimeInterval(AppConfig.load().presence.gracePeriod)
        wasAbsent = false
        confirming = false
        closeCamera()
        state = .watching(facePresent: true)
    }

    @objc private func sessionResignedActive() {
        // 锁屏/切换用户时暂停计时,回来后重新宽限(由 becameActive 处理);
        // 注册中同样取消,避免切用户后摄像头还开着
        confirming = false
        cancelEnroll(restart: false)
        if state == .enrolling { state = .off }
        closeCamera()
        graceUntil = .distantFuture
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension PresenceMonitor: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // 确认窗口内的每一帧都做检测:任一人脸即判有人(避免头几帧未曝光导致的误判)
        confirmLock.lock()
        let enrolling = enrollSamples != nil
        let settled = confirmResult != nil
        var warmup = 0
        if enrolling || !settled {
            if warmupFramesRemaining > 0 {
                warmupFramesRemaining -= 1
                warmup = 1
            }
        }
        confirmLock.unlock()
        // 看守模式已出结论则忽略后续帧;注册模式持续采集直到采够;预热帧不检测只丢弃
        if !enrolling, settled { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if warmup == 1 { return }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNSequenceRequestHandler()
        var faces: [VNFaceObservation] = []
        if (try? handler.perform([request], on: pixelBuffer)) != nil {
            faces = request.results ?? []
        }
        let seen = !faces.isEmpty
        // 曝光稳定帧缓存为快照候选,锁屏时写入
        confirmLock.lock()
        latestFrame = pixelBuffer
        confirmLock.unlock()
        if enrolling {
            // 注册:取最大人脸提特征攒样本;够数后主线程收尾(超时由注册定时器兜底)
            guard seen, let box = Self.largestFace(faces),
                  let fp = Self.faceFeaturePrint(pixelBuffer, faceBox: box) else { return }
            confirmLock.lock()
            enrollSamples?.append(fp)
            let n = enrollSamples?.count ?? 0
            let t = enrollTarget
            // 置收尾标记,超时轮询见到标记就只停表不再收尾
            let shouldFinish = n >= t && !enrollFinishing
            if shouldFinish { enrollFinishing = true }
            confirmLock.unlock()
            if shouldFinish {
                Task { @MainActor in PresenceMonitor.shared.finishEnroll(success: true) }
            }
            return
        }
        if seen {
            confirmLock.lock()
            confirmResult = true
            confirmLock.unlock()
            presenceDebugLog("captureOutput: 检测到人脸 → confirmResult=true")
            // 陌生人锁:只在首个见人帧算一次相似度,存下来给主线程收尾用
            let pcfg = AppConfig.load().presence
            if pcfg.strangerLockEnabled, let owner = pcfg.ownerFaceprint,
               let box = Self.largestFace(faces),
               let fp = Self.faceFeaturePrint(pixelBuffer, faceBox: box) {
                let score = Faceprint.cosineSimilarity(owner, fp)
                confirmLock.lock()
                if confirmOwnerScore == nil { confirmOwnerScore = score }
                confirmLock.unlock()
                presenceDebugLog("陌生人比对:相似度 \(String(format: "%.2f", score))")
            }
        }
    }

    /// 多张脸时取面积最大的框(离镜头最近、最可能是正主)
    private nonisolated static func largestFace(_ faces: [VNFaceObservation]) -> VNFaceObservation? {
        faces.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
    }

    /// 人脸区域提 Vision 特征向量:按归一化框裁出人脸小图,再算 featureprint。
    /// nil=提失败(框太小/无特征),调用方跳过该帧即可。
    private nonisolated static func faceFeaturePrint(
        _ pixelBuffer: CVPixelBuffer,
        faceBox: VNFaceObservation
    ) -> [Float]? {
        let box = faceBox.boundingBox
        // 框太小(远景/误检)不提,避免垃圾特征污染注册与比对
        guard box.width >= 0.08, box.height >= 0.08 else { return nil }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        // Vision 归一化框(左下原点)转像素框(左上原点,与 CGImage 一致),
        // 外扩 15% 含下巴与发际,并钳制在画面内
        var rect = CGRect(
            x: box.minX * CGFloat(w),
            y: (1.0 - box.maxY) * CGFloat(h),
            width: box.width * CGFloat(w),
            height: box.height * CGFloat(h)
        )
        rect = rect.insetBy(dx: -rect.width * 0.15, dy: -rect.height * 0.15)
            .intersection(CGRect(x: 0, y: 0, width: w, height: h))
        guard !rect.isNull, rect.width >= 40, rect.height >= 40 else { return nil }
        let full = CIImage(cvPixelBuffer: pixelBuffer)
        guard let fullCG = CIContext().createCGImage(full, from: full.extent),
              let faceCG = fullCG.cropping(to: rect.integral) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNSequenceRequestHandler()
        guard (try? handler.perform([request], on: faceCG)) != nil,
              let obs = request.results?.first else { return nil }
        var floats: [Float] = []
        floats.reserveCapacity(obs.elementCount)
        let ok = obs.data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress, raw.count >= obs.elementCount * MemoryLayout<Float>.size else {
                return false
            }
            let ptr = base.assumingMemoryBound(to: Float.self)
            floats.append(contentsOf: UnsafeBufferPointer(start: ptr, count: obs.elementCount))
            return true
        }
        guard ok, !floats.isEmpty else { return nil }
        return floats
    }

    /// 把无人判定帧存到本机磁盘(仅当配置开启);后台执行,不阻塞锁屏
    private nonisolated static func saveCaptureSnapshot(_ pixelBuffer: CVPixelBuffer) {
        guard AppConfig.load().presence.saveCaptureOnLock else { return }
        let dir = ConfigStore.configURL
            .deletingLastPathComponent()
            .appendingPathComponent("presence-cap", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = dir.appendingPathComponent("presence-\(formatter.string(from: Date())).png")
        // 前置摄像头需水平镜像,否则看的人是反的
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(CGImagePropertyOrientation.downMirrored)
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else {
            FlowLog.general.info("人脸看守:快照编码失败")
            return
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            FlowLog.general.info("人脸看守:快照 PNG 编码失败")
            return
        }
        try? data.write(to: url)
        FlowLog.general.info("人脸看守:已保存锁屏前快照 \(url.lastPathComponent)")
    }
}
