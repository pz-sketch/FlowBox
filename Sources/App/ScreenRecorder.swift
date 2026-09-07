@preconcurrency import AVFoundation
import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import os
import ScreenCaptureKit
import SharedCore

// MARK: - 录屏管理(全屏 + 带声 + 可选摄像头画中画)

@MainActor
final class ScreenRecorder: NSObject {

    static let shared = ScreenRecorder()

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var micSession: AVCaptureSession?
    private var micOutput: AVCaptureAudioDataOutput?
    private var outputURL: URL?
    private var controlPanel: RecordingControlPanel?
    private var countdownPanel: CountdownPanel?
    private var cameraPanel: CameraPreviewPanel?
    private var timer: Timer?
    private var startedAt: Date?
    private var hasStartedSession = false
    private var countdownToken = UUID()
    private var countdownKeyMonitor: Any?
    private var isFinishing = false

    // 视频尺寸/帧率(用于合成)
    private var outW: Int = 0
    private var outH: Int = 0
    private var outFPS: Int = 30

    // 摄像头画中画
    private var cameraSession: AVCaptureSession?
    private var cameraOutput: AVCaptureVideoDataOutput?
    private var cameraDevice: AVCaptureDevice?
    private var latestCameraPixelBuffer: CVPixelBuffer?
    private var cameraPixelLock = NSLock()
    private var cameraEnabled = false

    private(set) var isRecording = false
    private(set) var isCountingDown = false

    // MARK: - 对外入口

    func toggle() {
        if isRecording || isCountingDown { stop() } else { start() }
    }

    func start() {
        guard !isRecording, !isCountingDown else { return }
        FlowLog.recording.info("录屏 start 请求 screens=\(NSScreen.screens.count)")
        guard CGPreflightScreenCaptureAccess() else {
            FlowLog.permission.info("录屏:屏幕录制权限未授权")
            CGRequestScreenCaptureAccess()
            let alert = NSAlert()
            alert.messageText = L10n.tr("需要「屏幕录制」权限", "Screen Recording Permission Required")
            alert.informativeText = L10n.tr("录屏前，请到 系统设置 → 隐私与安全性 → 屏幕录制 中允许「FlowBox」，然后退出本应用（菜单栏图标 → 退出）并重新打开。", "Before recording, allow FlowBox in System Settings → Privacy & Security → Screen Recording, then quit and reopen the app.")
            alert.alertStyle = .warning
            alert.addButton(withTitle: L10n.tr("打开系统设置", "Open System Settings"))
            alert.addButton(withTitle: L10n.tr("取消", "Cancel"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        let cfg = AppConfig.load().recording
        // 摄像头权限:若开启摄像头且未授权,先请求
        if cfg.captureCamera {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        FlowLog.recording.info("摄像头授权结果: \(granted)")
                        if granted { self.checkMicThenStart() }
                        else { self.showCameraDeniedAlertAndStartWithoutCamera() }
                    }
                }
                return
            case .denied, .restricted:
                FlowLog.permission.info("摄像头权限被拒绝")
                showCameraDeniedAlertAndStartWithoutCamera()
                return
            default: break
            }
        }
        checkMicThenStart()
    }

    private func checkMicThenStart() {
        let cfg = AppConfig.load().recording
        if cfg.captureMicrophone {
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        FlowLog.recording.info("麦克风授权结果: \(granted)")
                        if granted { self.startWithCountdown() }
                        else { self.showMicDeniedAlert() }
                    }
                }
                return
            case .denied, .restricted:
                FlowLog.permission.info("麦克风权限被拒绝")
                showMicDeniedAlert()
                return
            default: break
            }
        }
        startWithCountdown()
    }

    func stop() {
        guard (isRecording || isCountingDown), !isFinishing else { return }
        FlowLog.recording.info("录屏 stop 请求 isRecording=\(self.isRecording) isCountingDown=\(self.isCountingDown)")
        countdownToken = UUID()
        countdownPanel?.orderOut(nil)
        countdownPanel = nil
        countdownKeyMonitor.map { NSEvent.removeMonitor($0) }
        countdownKeyMonitor = nil
        let wasCountingDown = isCountingDown
        isCountingDown = false
        timer?.invalidate()
        timer = nil
        if wasCountingDown, !isRecording {
            // 倒计时阶段取消,收回摄像头预览与会话
            hideCameraPanel()
            stopCameraCapture()
            cameraEnabled = false
            latestCameraPixelBuffer = nil
            return
        }
        guard isRecording else { return }
        Task { await finishWriting(cancelled: false) }
    }

    func cancel() {
        guard !isFinishing else { return }
        countdownToken = UUID()
        countdownPanel?.orderOut(nil)
        countdownPanel = nil
        countdownKeyMonitor.map { NSEvent.removeMonitor($0) }
        countdownKeyMonitor = nil
        let wasCountingDown = isCountingDown
        isCountingDown = false
        timer?.invalidate()
        timer = nil
        if wasCountingDown, !isRecording {
            hideCameraPanel()
            stopCameraCapture()
            cameraEnabled = false
            latestCameraPixelBuffer = nil
            return
        }
        if isRecording {
            Task { await finishWriting(cancelled: true) }
        }
    }

    // MARK: - 倒计时

    private func startWithCountdown() {
        isCountingDown = true
        // 摄像头提前预热并立即弹出预览,避免录制开始后1秒才出现
        let rcfg = AppConfig.load().recording
        if rcfg.captureCamera, AVCaptureDevice.authorizationStatus(for: .video) != .denied,
           AVCaptureDevice.authorizationStatus(for: .video) != .restricted {
            cameraEnabled = true
            latestCameraPixelBuffer = nil
            if cameraSession == nil { startCameraCaptureIfNeeded() }
            showCameraPanel()
        }
        let token = UUID()
        countdownToken = token
        let panel = CountdownPanel(recorder: self)
        panel.orderFront(nil)
        countdownPanel = panel
        countdownKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancel()
            return nil
        }
        var n = 3
        panel.showNumber(n)
        NSSound(named: NSSound.Name("Tink"))?.play()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self else { return }
            Task { @MainActor in
                guard self.isCountingDown, self.countdownToken == token else { t.invalidate(); return }
                n -= 1
                if n > 0 {
                    panel.showNumber(n); NSSound(named: NSSound.Name("Tink"))?.play()
                } else if n == 0 {
                    panel.showGo()
                } else {
                    t.invalidate()
                    self.timer = nil
                    self.countdownKeyMonitor.map { NSEvent.removeMonitor($0) }
                    self.countdownKeyMonitor = nil
                    guard self.isCountingDown, self.countdownToken == token else { return }
                    panel.orderOut(nil)
                    self.countdownPanel = nil
                    self.isCountingDown = false
                    await self.beginCapture()
                }
            }
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    // MARK: - 开始采集

    private func beginCapture() async {
        let cfg = AppConfig.load().recording
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let baseURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("录屏 \(formatter.string(from: Date())).mov")
        // 避免同秒内重名导致 AVAssetWriter 创建失败
        var url = baseURL
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let name = "录屏 \(formatter.string(from: Date())) \(n).mov"
            url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop").appendingPathComponent(name)
            n += 1
            if n > 99 { break }
        }
        outputURL = url

        guard let screen = NSScreen.main else {
            showError(L10n.tr("未找到主显示器", "Main display not found"))
            return
        }
        let scale = screen.backingScaleFactor
        let w = Int(screen.frame.width * scale)
        let h = Int(screen.frame.height * scale)
        let fps = max(15, min(60, cfg.frameRate))
        outW = w
        outH = h
        outFPS = fps
        // 摄像头若在倒计时已预热则复用,避免重复启动导致黑屏1秒
        if cameraEnabled != cfg.captureCamera { cameraEnabled = cfg.captureCamera }
        if cameraEnabled, cameraSession == nil {
            latestCameraPixelBuffer = nil
        } else if !cameraEnabled {
            latestCameraPixelBuffer = nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: {
                Int($0.frame.width) == Int(screen.frame.width) && Int($0.frame.height) == Int(screen.frame.height)
            }) ?? content.displays.first else {
                showError(L10n.tr("未找到可录制的显示器", "No recordable display found"))
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let scConfig = SCStreamConfiguration()
            scConfig.width = w
            scConfig.height = h
            scConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            scConfig.queueDepth = 6
            scConfig.showsCursor = true
            scConfig.capturesAudio = cfg.captureSystemAudio
            if cfg.captureSystemAudio {
                scConfig.sampleRate = 48000
                scConfig.channelCount = 2
            }

            let stream = SCStream(filter: filter, configuration: scConfig, delegate: self)
            self.stream = stream

            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: w,
                AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [
                    AVVideoExpectedSourceFrameRateKey: fps,
                    AVVideoAverageBitRateKey: 8_000_000,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                ] as [String: Any],
            ]
            let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            vInput.expectsMediaDataInRealTime = true
            if writer.canAdd(vInput) { writer.add(vInput) }
            videoInput = vInput

            if cfg.captureSystemAudio {
                let aSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128000,
                ]
                let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: aSettings)
                aInput.expectsMediaDataInRealTime = true
                if writer.canAdd(aInput) { writer.add(aInput) }
                audioInput = aInput
            }

            if cfg.captureMicrophone {
                let mSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderBitRateKey: 96000,
                ]
                let mInput = AVAssetWriterInput(mediaType: .audio, outputSettings: mSettings)
                mInput.expectsMediaDataInRealTime = true
                if writer.canAdd(mInput) { writer.add(mInput) }
                micInput = mInput
            }

            self.writer = writer

            let queue = DispatchQueue.global(qos: .userInitiated)
            try stream.addStreamOutput(self, type: SCStreamOutputType.screen, sampleHandlerQueue: queue)
            if cfg.captureSystemAudio {
                try stream.addStreamOutput(self, type: SCStreamOutputType.audio, sampleHandlerQueue: queue)
            }
            if cfg.captureMicrophone {
                startMicCaptureIfNeeded()
            }
            if cameraEnabled, cameraSession == nil {
                startCameraCaptureIfNeeded()
            }

            try await stream.startCapture()
            writer.startWriting()

            isRecording = true
            startedAt = Date()
            hasStartedSession = false
            showControlPanel()
            if cameraEnabled, cameraPanel == nil {
                showCameraPanel()
            }
            NSLog("[录屏] 开始: \(url.lastPathComponent) \(w)x\(h)@\(fps)fps 系统声:\(cfg.captureSystemAudio) 麦:\(cfg.captureMicrophone) 摄像头:\(cfg.captureCamera)")

        } catch {
            showError(L10n.tr("开始录制失败：\n\(error.localizedDescription)", "Failed to start recording:\n\(error.localizedDescription)"))
            cleanup()
        }
    }

    // MARK: - AVCapture 麦克风

    private func startMicCaptureIfNeeded() {
        guard let device = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: device) else {
            NSLog("[录屏] 未找到麦克风设备")
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInitiated))
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        micSession = session
        micOutput = output
        let sess = session
        DispatchQueue.global(qos: .userInitiated).async { sess.startRunning() }
    }

    // MARK: - 摄像头采集

    private func startCameraCaptureIfNeeded() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video) else {
            NSLog("[录屏] 未找到摄像头")
            cameraEnabled = false
            return
        }
        cameraDevice = device
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            NSLog("[录屏] 摄像头输入创建失败")
            cameraEnabled = false
            return
        }
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        output.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInitiated))
        if session.canAddOutput(output) { session.addOutput(output) }
        if let conn = output.connection(with: .video) {
            if conn.isVideoMirroringSupported {
                conn.isVideoMirrored = AppConfig.load().recording.cameraMirrored
            }
        }
        session.commitConfiguration()
        cameraSession = session
        cameraOutput = output
        let sess = session
        DispatchQueue.global(qos: .userInitiated).async { sess.startRunning() }
        NSLog("[录屏] 摄像头已启动: \(device.localizedName)")
    }

    private func stopCameraCapture() {
        cameraSession?.stopRunning()
        cameraSession = nil
        cameraOutput = nil
        cameraDevice = nil
        cameraPixelLock.lock()
        latestCameraPixelBuffer = nil
        cameraPixelLock.unlock()
    }

    // 预览窗口

    private func showCameraPanel() {
        let panel = CameraPreviewPanel(session: cameraSession, recorder: self)
        panel.orderFront(nil)
        cameraPanel = panel
    }

    private func hideCameraPanel() {
        cameraPanel?.orderOut(nil)
        cameraPanel = nil
    }

    // MARK: - 写入样本(含画中画合成)

    private func appendSample(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard let writer, let vInput = videoInput, isRecording else { return }
        if !hasStartedSession, type == SCStreamOutputType.screen {
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            if pts.isValid { writer.startSession(atSourceTime: pts) }
            else { writer.startSession(atSourceTime: .zero) }
            hasStartedSession = true
            startedAt = Date()
        }
        guard hasStartedSession else { return }
        switch type {
        case SCStreamOutputType.screen:
            // 摄像头叠加:把当前帧合成后写入
            if cameraEnabled, let composed = compositedSampleBuffer(from: sampleBuffer) {
                if vInput.isReadyForMoreMediaData { vInput.append(composed) }
            } else {
                if vInput.isReadyForMoreMediaData { vInput.append(sampleBuffer) }
            }
        case SCStreamOutputType.audio:
            if let aInput = audioInput, aInput.isReadyForMoreMediaData { aInput.append(sampleBuffer) }
        default:
            break
        }
    }

    /// 将摄像头画面以画中画合成到屏幕帧上,返回新的 CMSampleBuffer
    private func compositedSampleBuffer(from sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let srcPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        cameraPixelLock.lock()
        let camPB = latestCameraPixelBuffer
        cameraPixelLock.unlock()
        guard let camPB else { return nil }

        let cfg = AppConfig.load().recording
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        guard let outPB = VideoCompositor.compositedPixelBuffer(
            srcPixelBuffer: srcPixelBuffer,
            camPixelBuffer: camPB,
            config: cfg,
            outputW: outW,
            outputH: outH,
            scale: scale
        ) else {
            FlowLog.recording.error("画中画合成失败,回退原帧")
            return nil
        }
        let timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            decodeTimeStamp: CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
        )
        return VideoCompositor.newSampleBuffer(from: outPB, timing: timing)
    }

    private func appendMicSample(_ sampleBuffer: CMSampleBuffer) {
        guard isRecording, hasStartedSession, let mInput = micInput, mInput.isReadyForMoreMediaData else { return }
        mInput.append(sampleBuffer)
    }

    private func appendCameraSample(_ sampleBuffer: CMSampleBuffer) {
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        cameraPixelLock.lock()
        latestCameraPixelBuffer = pb
        cameraPixelLock.unlock()
        // 同时刷新预览
        Task { @MainActor in
            self.cameraPanel?.updateFrame(pb)
        }
    }

    // MARK: - 结束

    private func finishWriting(cancelled: Bool) async {
        guard !isFinishing else { return }
        isFinishing = true
        isRecording = false
        timer?.invalidate()
        timer = nil
        if cancelled { controlPanel?.closePanel() }
        else { controlPanel?.showSaving() }
        hideCameraPanel()
        stopCameraCapture()

        micSession?.stopRunning()
        micSession = nil
        micOutput = nil

        do { try await stream?.stopCapture() } catch {
            FlowLog.recording.error("stopCapture 失败: \(error.localizedDescription, privacy: .public)")
        }
        stream = nil

        guard let writer else { cleanup(); return }
        if cancelled {
            writer.cancelWriting()
            if let url = outputURL { try? FileManager.default.removeItem(at: url) }
            cleanup()
            FlowLog.recording.info("录制已取消")
            ToastWindow.show(text: L10n.tr("已取消录制", "Recording Cancelled"), at: panelCenter())
            return
        }
        videoInput?.markAsFinished()
        audioInput?.markAsFinished()
        micInput?.markAsFinished()
        await writer.finishWriting()
        let url = outputURL
        let success = writer.status == .completed
        let errDesc = writer.error?.localizedDescription ?? "nil"
        let statusRaw = writer.status.rawValue
        FlowLog.recording.info("finishWriting status=\(statusRaw) success=\(success) error=\(errDesc, privacy: .public) url=\(self.outputURL?.path ?? "nil", privacy: .public)")
        cleanup()
        if success, let url {
            let center = panelCenter()
            ToastWindow.show(text: L10n.tr("已保存到桌面", "Saved to Desktop"), at: center)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            FlowLog.recording.info("完成: \(url.path, privacy: .public)")
        } else if !success {
            showError(L10n.tr("保存失败（状态 \(statusRaw)）：\(errDesc)", "Failed to save (status \(statusRaw)): \(errDesc)"))
            if let url { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func cleanup() {
        controlPanel?.closePanel()
        controlPanel = nil
        isFinishing = false
        isRecording = false
        hasStartedSession = false
        stream = nil
        writer = nil
        videoInput = nil
        audioInput = nil
        micInput = nil
        outputURL = nil
        startedAt = nil
        stopCameraCapture()
        cameraEnabled = false
        hideCameraPanel()
    }

    private func showControlPanel() {
        let panel = RecordingControlPanel(recorder: self)
        panel.orderFront(nil)
        controlPanel = panel
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let start = self.startedAt else { return }
                let sec = Int(Date().timeIntervalSince(start))
                self.controlPanel?.updateTime(sec)
            }
        }
        if let t = timer { RunLoop.main.add(t, forMode: .common) }
    }

    private func panelCenter() -> NSPoint {
        if let s = NSScreen.main { return NSPoint(x: s.frame.midX, y: s.frame.midY) }
        return NSPoint(x: 600, y: 400)
    }

    private func showError(_ text: String) {
        let alert = NSAlert()
        alert.messageText = L10n.tr("录屏", "Recording")
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好的")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showMicDeniedAlert() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("需要「麦克风」权限", "Microphone Permission Required")
        alert.informativeText = L10n.tr("请到 系统设置 → 隐私与安全性 → 麦克风 中允许「FlowBox」,然后重试。若不想录麦克风,可在设置里关闭该选项。", "Please allow FlowBox in System Settings → Privacy & Security → Microphone. Or turn off mic in Settings if you don't need it.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("打开系统设置", "Open System Settings"))
        alert.addButton(withTitle: L10n.tr("取消", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showCameraDeniedAlertAndStartWithoutCamera() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("需要「摄像头」权限", "Camera Permission Required")
        alert.informativeText = L10n.tr("请到 系统设置 → 隐私与安全性 → 摄像头 中允许「FlowBox」,然后重试。已为你临时关闭摄像头后开始录制,也可在设置里关闭摄像头选项。", "Please allow FlowBox in System Settings → Privacy & Security → Camera, then retry. Recording will continue without camera for now; you can also turn it off in Settings.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.tr("打开系统设置", "Open System Settings"))
        alert.addButton(withTitle: L10n.tr("继续录制(无摄像头)", "Continue Without Camera"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
        // 不管点哪个,都继续走麦克风检查并开始录制(本次无摄像头)
        var cfg = AppConfig.load()
        let wasEnabled = cfg.recording.captureCamera
        cfg.recording.captureCamera = false
        // 不自动写回,仅本次生效;但给个提示
        _ = wasEnabled
        checkMicThenStart()
        // 临时压制:本次录制不启用摄像头
        cameraEnabled = false
    }
}

// MARK: - SCStream 输出

extension ScreenRecorder: SCStreamOutput, SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        Task { @MainActor in self.appendSample(sampleBuffer, type: type) }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[录屏] 流中断: \(error.localizedDescription)")
        Task { @MainActor in
            if self.isRecording { await self.finishWriting(cancelled: false) }
        }
    }
}

// MARK: - AVCapture 代理

extension ScreenRecorder: AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output is AVCaptureAudioDataOutput {
            Task { @MainActor in self.appendMicSample(sampleBuffer) }
        } else if output is AVCaptureVideoDataOutput {
            Task { @MainActor in self.appendCameraSample(sampleBuffer) }
        }
    }
}

// MARK: - 摄像头预览浮窗(可拖动)

private final class CameraPreviewPanel: NSPanel {

    private weak var recorder: ScreenRecorder?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var session: AVCaptureSession?
    private var dragStart: NSPoint = .zero
    private var frameStart: NSPoint = .zero
    private var isDragging = false
    private let container = NSView()

    init(session: AVCaptureSession?, recorder: ScreenRecorder) {
        self.session = session
        self.recorder = recorder
        let cfg = AppConfig.load().recording
        let w = max(120, min(360, cfg.cameraWidth))
        let h = cfg.cameraIsCircle ? w : w * 9 / 16
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 16
        var origin: NSPoint
        if cfg.cameraX >= 0, cfg.cameraY >= 0 {
            // 归一化 → 屏幕坐标(顶左)
            let px = CGFloat(cfg.cameraX) * (screenFrame.width - w)
            let py = CGFloat(cfg.cameraY) * (screenFrame.height - h)
            // 归一化存的是左下,转顶左
            origin = NSPoint(x: screenFrame.minX + px, y: screenFrame.maxY - py - h - margin * 2)
            // 旧值范围保护
            origin.x = max(screenFrame.minX + 4, min(origin.x, screenFrame.maxX - w - 4))
            origin.y = max(screenFrame.minY + 4, min(origin.y, screenFrame.maxY - h - 4))
        } else {
            origin = NSPoint(x: screenFrame.maxX - w - margin, y: screenFrame.maxY - h - margin - 44)
        }
        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: w, height: h)),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        sharingType = .none

        container.frame = NSRect(x: 0, y: 0, width: w, height: h)
        container.wantsLayer = true
        container.layer?.cornerRadius = cfg.cameraIsCircle ? h / 2 : 12
        container.layer?.masksToBounds = true
        container.layer?.borderColor = NSColor.white.cgColor
        container.layer?.borderWidth = 2
        container.layer?.backgroundColor = NSColor.black.cgColor
        contentView = container

        if let session {
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.frame = container.bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer.videoGravity = .resizeAspectFill
            if let conn = layer.connection, conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = false
                conn.isVideoMirrored = cfg.cameraMirrored
            }
            container.layer?.addSublayer(layer)
            previewLayer = layer
        } else {
            let label = NSTextField(labelWithString: L10n.tr("摄像头不可用", "Camera Unavailable"))
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .white
            label.alignment = .center
            label.frame = NSRect(x: 0, y: h/2 - 10, width: w, height: 20)
            label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
            container.addSubview(label)
        }

        // 提示
        let hint = NSTextField(labelWithString: L10n.tr("拖动可移动 · 位置会记忆", "Drag to move · Position is remembered"))
        hint.font = .systemFont(ofSize: 10, weight: .medium)
        hint.textColor = .white
        hint.backgroundColor = NSColor.black.withAlphaComponent(0.55)
        hint.drawsBackground = true
        hint.isBezeled = false
        hint.alignment = .center
        hint.wantsLayer = true
        hint.layer?.cornerRadius = 6
        hint.layer?.masksToBounds = true
        hint.frame = NSRect(x: 6, y: 6, width: w - 12, height: 18)
        hint.autoresizingMask = [.width, .minYMargin]
        container.addSubview(hint)
        // 2秒后淡出提示
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                hint.animator().alphaValue = 0
            }
        }
        NSLog("[录屏] 摄像头预览已创建: \(w)x\(h) at \(origin)")
    }

    func updateFrame(_ pixelBuffer: CVPixelBuffer) {
        // 使用 PreviewLayer 时无需手动刷新,保留此方法兼容合成逻辑
    }

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        dragStart = NSEvent.mouseLocation
        frameStart = frame.origin
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let cur = NSEvent.mouseLocation
        let dx = cur.x - dragStart.x
        let dy = cur.y - dragStart.y
        var origin = NSPoint(x: frameStart.x + dx, y: frameStart.y + dy)
        if let screen = NSScreen.main {
            let f = screen.frame
            origin.x = max(f.minX + 4, min(origin.x, f.maxX - frame.width - 4))
            origin.y = max(f.minY + 4, min(origin.y, f.maxY - frame.height - 4))
        }
        setFrameOrigin(origin)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        savePosition()
    }

    private func savePosition() {
        guard let screen = NSScreen.main else { return }
        let f = screen.frame
        let w = frame.width
        let h = frame.height
        // 存归一化(左下原点)
        let normX = (frame.minX - f.minX) / max(1, f.width - w)
        let normY = (f.maxY - frame.maxY) / max(1, f.height - h)
        var cfg = AppConfig.load()
        cfg.recording.cameraX = max(0, min(1, Double(normX)))
        cfg.recording.cameraY = max(0, min(1, Double(normY)))
        cfg.write()
        NSLog("[录屏] 摄像头位置已记忆: x=\(cfg.recording.cameraX) y=\(cfg.recording.cameraY)")
    }

    override var canBecomeKey: Bool { false }
}

// MARK: - 顶部悬浮控制条

private final class RecordingControlPanel: NSPanel {
    private weak var recorder: ScreenRecorder?
    private let timeLabel = NSTextField(labelWithString: L10n.tr("● 录制中 00:00", "● Recording 00:00"))
    private var dotOn = true
    private var blinkTimer: Timer?
    private var actionButtons: [NSButton] = []

    init(recorder: ScreenRecorder) {
        self.recorder = recorder
        let w: CGFloat = 300, h: CGFloat = 36
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: screenFrame.midX - w / 2, y: screenFrame.maxY - h - 24)
        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: w, height: h)),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        sharingType = .none

        let container = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.14, alpha: 0.92).cgColor
        container.layer?.cornerRadius = 12
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        container.layer?.borderWidth = 1
        contentView = container

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        timeLabel.textColor = .white
        timeLabel.alignment = .left
        timeLabel.frame = NSRect(x: 14, y: 9, width: 130, height: 18)
        container.addSubview(timeLabel)

        let sep = NSView(frame: NSRect(x: 150, y: 6, width: 1, height: 24))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        container.addSubview(sep)

        func pill(_ title: String, systemImage: String, bg: NSColor, fg: NSColor, action: Selector) -> NSButton {
            let b = NSButton(title: "", target: self, action: action)
            b.bezelStyle = .inline
            b.isBordered = false
            b.wantsLayer = true
            b.layer?.backgroundColor = bg.cgColor
            b.layer?.cornerRadius = 8
            if let img = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) {
                img.isTemplate = true
                b.image = img
                b.imagePosition = .imageLeading
            }
            b.attributedTitle = NSAttributedString(string: title, attributes: [
                .foregroundColor: fg, .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            ])
            b.contentTintColor = fg
            b.setAccessibilityElement(true)
            b.setAccessibilityLabel(title)
            b.setAccessibilityHelp(title)
            return b
        }
        let stop = pill(L10n.tr("停止", "Stop"), systemImage: "stop.fill", bg: NSColor.systemRed, fg: .white, action: #selector(doStop))
        stop.frame = NSRect(x: 160, y: 5, width: 66, height: 26)
        container.addSubview(stop)
        actionButtons.append(stop)

        let cancel = pill(L10n.tr("取消", "Cancel"), systemImage: "xmark", bg: NSColor.white, fg: NSColor(white: 0.2, alpha: 1), action: #selector(doCancel))
        cancel.frame = NSRect(x: 232, y: 5, width: 60, height: 26)
        cancel.layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor
        cancel.layer?.borderWidth = 1
        container.addSubview(cancel)
        actionButtons.append(cancel)
        timeLabel.setAccessibilityElement(true)
        timeLabel.setAccessibilityLabel(L10n.tr("录制状态", "Recording status"))
        container.setAccessibilityElement(true)
        container.setAccessibilityLabel(L10n.tr("录屏控制条", "Recording controls"))

        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.dotOn.toggle()
            self.timeLabel.textColor = self.dotOn ? .white : .white.withAlphaComponent(0.5)
        }
        if let t = blinkTimer { RunLoop.main.add(t, forMode: .common) }
    }

    func updateTime(_ seconds: Int) {
        let m = seconds / 60, s = seconds % 60
        timeLabel.stringValue = String(format: L10n.tr("● 录制中 %02d:%02d", "● Recording %02d:%02d"), m, s)
    }

    func showSaving() {
        timeLabel.stringValue = L10n.tr("正在保存…", "Saving…")
        timeLabel.setAccessibilityLabel(L10n.tr("正在保存录屏", "Saving recording"))
        actionButtons.forEach { $0.isEnabled = false; $0.alphaValue = 0.5 }
        blinkTimer?.invalidate()
        blinkTimer = nil
    }

    func closePanel() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        orderOut(nil)
    }

    @objc private func doStop() { recorder?.stop() }
    @objc private func doCancel() { recorder?.cancel() }

    override var canBecomeKey: Bool { false }
}

// MARK: - 倒计时全屏提示

private final class CountdownPanel: NSPanel {
    private weak var recorder: ScreenRecorder?
    private let label = NSTextField(labelWithString: "")

    init(recorder: ScreenRecorder) {
        self.recorder = recorder
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 4)
        isOpaque = false
        backgroundColor = NSColor.black.withAlphaComponent(0.35)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
        hidesOnDeactivate = false
        sharingType = .none

        label.font = .systemFont(ofSize: 120, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.frame = NSRect(x: frame.width / 2 - 120, y: frame.height / 2 - 60, width: 240, height: 140)
        label.setAccessibilityElement(true)
        label.setAccessibilityLabel(L10n.tr("录屏倒计时", "Recording countdown"))
        contentView?.addSubview(label)

        let hint = NSTextField(labelWithString: L10n.tr("即将开始全屏录制  ·  顶部控制条可停止", "Fullscreen recording will start  ·  Use top bar to stop"))
        hint.font = .systemFont(ofSize: 14, weight: .medium)
        hint.textColor = .white.withAlphaComponent(0.9)
        hint.alignment = .center
        hint.frame = NSRect(x: frame.width / 2 - 200, y: frame.height / 2 - 100, width: 400, height: 20)
        hint.setAccessibilityElement(true)
        hint.setAccessibilityLabel(L10n.tr("录屏提示：按 Esc 取消", "Recording hint: press Esc to cancel"))
        contentView?.addSubview(hint)

        let cancel = NSButton(title: L10n.tr("取消录制", "Cancel Recording"), target: self, action: #selector(cancelRecording))
        cancel.bezelStyle = .rounded
        cancel.frame = NSRect(x: frame.width / 2 - 70, y: frame.height / 2 - 145, width: 140, height: 30)
        cancel.setAccessibilityLabel(L10n.tr("取消录制", "Cancel recording"))
        cancel.setAccessibilityHelp(L10n.tr("按 Esc 也可取消", "Press Esc to cancel"))
        contentView?.addSubview(cancel)
    }

    @objc private func cancelRecording() { recorder?.cancel() }

    func showNumber(_ n: Int) {
        label.stringValue = "\(n)"
        label.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            label.animator().alphaValue = 1
        }
    }
    func showGo() {
        label.stringValue = "●"
        label.textColor = .systemRed
        label.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            label.animator().alphaValue = 1
        }
    }
    override var canBecomeKey: Bool { false }
}
