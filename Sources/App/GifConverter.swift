import AppKit
import AVFoundation
import CoreGraphics
import ImageIO
import SharedCore
import UniformTypeIdentifiers

// MARK: - 录屏转 GIF:选视频 → 选帧率/宽度 → ImageIO 逐帧编码,输出到视频同目录

@MainActor
final class GifConverter {

    static let shared = GifConverter()

    private var panel: GifConvertPanel?

    /// 菜单入口:先选视频,再弹转换窗口
    func pickAndConvert() {
        NSApp.activate(ignoringOtherApps: true)
        let picker = NSOpenPanel()
        picker.title = L10n.tr("选择要转换为 GIF 的视频", "Choose a Video to Convert to GIF")
        picker.message = L10n.tr("可以选桌面上的录屏 .mov,或任意 mov/mp4/m4v 视频", "Pick a screen recording (.mov) from Desktop, or any mov/mp4/m4v video")
        picker.allowedContentTypes = [.movie, .mpeg4Movie]
        picker.allowsMultipleSelection = false
        picker.canChooseDirectories = false
        picker.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        picker.prompt = L10n.tr("选择", "Choose")
        guard picker.runModal() == .OK, let url = picker.url else { return }
        showPanel(for: url)
    }

    func showPanel(for sourceURL: URL) {
        if panel == nil { panel = GifConvertPanel() }
        NSApp.activate(ignoringOtherApps: true)
        panel?.show(for: sourceURL)
    }
}

// MARK: - GIF 编码任务

/// AVAssetImageGenerator 抽帧 → CGContext 缩放 → CGImageDestination 逐帧写入。
/// 全程在自有串行队列上执行,回调切回主线程;支持取消(删除半成品文件)。
final class GifEncodeJob {

    enum Outcome {
        case saved(URL)
        case cancelled
        case failed(String)
    }

    private let destURL: URL
    private let plan: GifEncodePlan
    private let generator: AVAssetImageGenerator
    private let queue = DispatchQueue(label: "net.ai2048.flowbox.gifencode")
    private let lock = NSLock()
    private var dest: CGImageDestination?
    private var isCancelled = false
    private var finalized = false
    private var processed = 0

    /// 主线程回调
    var onProgress: ((Int, Int) -> Void)?
    var onOutcome: ((Outcome) -> Void)?

    init(sourceURL: URL, destURL: URL, plan: GifEncodePlan) {
        self.destURL = destURL
        self.plan = plan
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: sourceURL))
        gen.appliesPreferredTrackTransform = true
        // 零容差取精确时间点的帧,保证 GIF 帧距均匀
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        self.generator = gen
    }

    func start() {
        queue.async { self.run() }
    }

    func cancel() {
        queue.async {
            self.lock.lock()
            self.isCancelled = true
            self.lock.unlock()
            self.generator.cancelAllCGImageGeneration()
            self.finish(cancelled: true)
        }
    }

    private func run() {
        lock.lock()
        let cancelled = isCancelled
        lock.unlock()
        guard !cancelled else { finish(cancelled: true); return }

        guard let dest = CGImageDestinationCreateWithURL(
            destURL as CFURL,
            UTType.gif.identifier as CFString,
            plan.frameCount,
            nil
        ) else {
            let msg = L10n.tr("无法创建 GIF 文件", "Cannot create GIF file")
            Task { @MainActor in self.onOutcome?(.failed(msg)) }
            return
        }
        // 循环次数 0 = 无限循环
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        lock.lock()
        self.dest = dest
        lock.unlock()

        let times = plan.frameTimes.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }
        generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] _, image, _, result, _ in
            // 结果汇到任务串行队列,与 cancel 串行化
            self?.queue.async { self?.handle(image: image, result: result) }
        }
    }

    private func handle(image: CGImage?, result: AVAssetImageGenerator.Result) {
        lock.lock()
        if isCancelled || finalized {
            lock.unlock()
            return
        }
        lock.unlock()

        var wrote = false
        if case .succeeded = result, let image, let dest = self.dest,
           let scaled = downscale(image) {
            CGImageDestinationAddImage(dest, scaled, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(plan.delayCS) / 100.0],
            ] as CFDictionary)
            wrote = true
        }
        // 单帧解码失败不中断:跳过继续,但计数必须推进,否则永远等不到收尾
        processed += 1
        let done = processed, total = plan.frameCount
        if wrote || done == total || done % 5 == 0 {
            Task { @MainActor in self.onProgress?(done, total) }
        }
        if done >= total {
            finish(cancelled: false)
        }
    }

    private func finish(cancelled: Bool) {
        lock.lock()
        guard !finalized else { lock.unlock(); return }
        finalized = true
        let dest = self.dest
        self.dest = nil
        lock.unlock()
        generator.cancelAllCGImageGeneration()

        if cancelled {
            try? FileManager.default.removeItem(at: destURL)
            Task { @MainActor in self.onOutcome?(.cancelled) }
            return
        }
        if let dest, CGImageDestinationFinalize(dest) {
            let url = destURL
            Task { @MainActor in self.onOutcome?(.saved(url)) }
        } else {
            try? FileManager.default.removeItem(at: destURL)
            let msg = L10n.tr("GIF 编码失败,请重试或换个视频", "GIF encoding failed, please retry or pick another video")
            Task { @MainActor in self.onOutcome?(.failed(msg)) }
        }
    }

    private func downscale(_ image: CGImage) -> CGImage? {
        guard image.width != plan.outW || image.height != plan.outH else { return image }
        let space = image.colorSpace?.model == .rgb ? image.colorSpace! : CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: plan.outW, height: plan.outH,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: plan.outW, height: plan.outH))
        return ctx.makeImage()
    }
}

// MARK: - 转换窗口

@MainActor
final class GifConvertPanel: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private var fileLabel: NSTextField!
    private var infoLabel: NSTextField!
    private var outLabel: NSTextField!
    private var fpsPopup: NSPopUpButton!
    private var widthPopup: NSPopUpButton!
    private var progress: NSProgressIndicator!
    private var statusLabel: NSTextField!
    private var convertButton: NSButton!

    private var sourceURL: URL?
    private var metaDuration: Double = 0
    private var metaW = 0
    private var metaH = 0
    private var job: GifEncodeJob?
    private var metaTask: Task<Void, Never>?

    private let fpsChoices = [5, 8, 10, 12, 15]
    private let widthChoices = [0, 1280, 960, 720, 480]

    func show(for url: URL) {
        if window == nil { build() }
        // 复用面板时若上一个任务还在跑,先取消(回调带身份校验,不会误刷新面板)
        job?.cancel()
        job = nil
        sourceURL = url
        fileLabel.stringValue = url.lastPathComponent
        metaDuration = 0
        metaW = 0
        metaH = 0
        statusLabel.stringValue = ""
        progress.isHidden = true
        setConverting(false)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        loadMetadata()
    }

    // MARK: UI 构建

    private func build() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.tr("录屏转 GIF", "Recording → GIF")
        win.backgroundColor = UIStyle.Palette.window
        win.isReleasedWhenClosed = false
        win.delegate = self
        window = win

        let root = UIStyle.vStack(spacing: UIStyle.Metrics.sp12)
        win.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: win.contentView!.topAnchor, constant: UIStyle.Metrics.sp20),
            root.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor, constant: UIStyle.Metrics.sp20),
            root.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor, constant: -UIStyle.Metrics.sp20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: win.contentView!.bottomAnchor, constant: -UIStyle.Metrics.sp16),
        ])

        fileLabel = UIStyle.label("—", font: UIStyle.Text.title(), color: UIStyle.Palette.text)
        fileLabel.lineBreakMode = .byTruncatingMiddle
        fileLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        root.addArrangedSubview(fileLabel)
        UIStyle.fillWidth(fileLabel, in: root)

        infoLabel = UIStyle.label(L10n.tr("正在读取视频信息…", "Reading video info…"),
                                  font: UIStyle.Text.caption(), color: UIStyle.Palette.textSecondary)
        root.addArrangedSubview(infoLabel)

        fpsPopup = NSPopUpButton()
        for f in fpsChoices {
            fpsPopup.addItem(withTitle: L10n.tr("\(f) 帧/秒", "\(f) fps"))
        }
        fpsPopup.target = self
        fpsPopup.action = #selector(settingsChanged)
        fpsPopup.setAccessibilityLabel(L10n.tr("GIF 帧率", "GIF frame rate"))
        root.addArrangedSubview(row(L10n.tr("帧率", "Frame rate"), fpsPopup))

        widthPopup = NSPopUpButton()
        let widthTitles = [
            L10n.tr("原始尺寸", "Original size"),
            "1280 px", "960 px", "720 px", "480 px",
        ]
        for t in widthTitles { widthPopup.addItem(withTitle: t) }
        widthPopup.target = self
        widthPopup.action = #selector(settingsChanged)
        widthPopup.setAccessibilityLabel(L10n.tr("GIF 最大宽度", "GIF maximum width"))
        root.addArrangedSubview(row(L10n.tr("宽度", "Width"), widthPopup))

        outLabel = UIStyle.label("", font: UIStyle.Text.caption(), color: UIStyle.Palette.textSecondary)
        root.addArrangedSubview(outLabel)
        UIStyle.fillWidth(outLabel, in: root)

        let statusRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        progress = NSProgressIndicator()
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.controlSize = .small
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.isHidden = true
        progress.setAccessibilityLabel(L10n.tr("转换进度", "Conversion progress"))
        statusRow.addArrangedSubview(progress)
        progress.widthAnchor.constraint(equalToConstant: 220).isActive = true
        statusLabel = UIStyle.label("", font: UIStyle.Text.caption(), color: UIStyle.Palette.textSecondary)
        statusRow.addArrangedSubview(statusLabel)
        root.addArrangedSubview(statusRow)

        let buttonRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp10)
        buttonRow.addArrangedSubview(UIStyle.spacer())
        let closeButton = UIStyle.secondaryButton(L10n.tr("关闭", "Close"), target: self, action: #selector(closeClicked))
        closeButton.keyEquivalent = "\u{1b}"
        buttonRow.addArrangedSubview(closeButton)
        convertButton = UIStyle.primaryButton(L10n.tr("开始转换", "Convert to GIF"), target: self, action: #selector(convertClicked))
        convertButton.keyEquivalent = "\r"
        convertButton.hasDestructiveAction = false
        convertButton.setAccessibilityLabel(L10n.tr("开始转换为 GIF", "Convert to GIF"))
        buttonRow.addArrangedSubview(convertButton)
        root.addArrangedSubview(buttonRow)
        UIStyle.fillWidth(buttonRow, in: root)

        let cfg = AppConfig.load().recording
        fpsPopup.selectItem(at: fpsChoices.firstIndex(of: min(15, max(2, cfg.gifFps))) ?? 2)
        widthPopup.selectItem(at: widthChoices.firstIndex(of: cfg.gifMaxWidth) ?? 2)
    }

    private func row(_ title: String, _ control: NSView) -> NSStackView {
        let s = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        let l = UIStyle.label(title, font: UIStyle.Text.body(), color: UIStyle.Palette.text)
        l.setAccessibilityLabel(title)
        s.addArrangedSubview(l)
        s.addArrangedSubview(control)
        control.widthAnchor.constraint(equalToConstant: 150).isActive = true
        return s
    }

    // MARK: 元数据读取

    private func loadMetadata() {
        guard let url = sourceURL else { return }
        metaTask?.cancel()
        infoLabel.stringValue = L10n.tr("正在读取视频信息…", "Reading video info…")
        convertButton.isEnabled = false
        outLabel.stringValue = ""
        let asset = AVURLAsset(url: url)
        metaTask = Task { [weak self] in
            let duration = (try? await asset.load(.duration).seconds) ?? 0
            // 必须按 preferredTransform 校正:竖拍/旋转视频的 naturalSize 是未旋转的,
            // 而抽帧时 appliesPreferredTrackTransform=true 返回旋转后的图,不校正会被拉伸
            var width = 0
            var height = 0
            if let track = try? await asset.loadTracks(withMediaType: .video).first {
                let natural = (try? await track.load(.naturalSize)) ?? .zero
                let transform = (try? await track.load(.preferredTransform)) ?? .identity
                let oriented = GifEncodePlan.orientedSize(natural: natural, transform: transform)
                width = oriented.width
                height = oriented.height
            }
            let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Double) ?? 0
            self?.applyMetadata(duration: duration, width: width, height: height, bytes: bytes)
        }
    }

    private func applyMetadata(duration: Double, width: Int, height: Int, bytes: Double) {
        guard !Task.isCancelled else { return }
        metaDuration = duration
        metaW = width
        metaH = height
        if duration <= 0 || width <= 0 {
            infoLabel.stringValue = L10n.tr("无法读取视频信息,请换个文件试试", "Cannot read video info, try another file")
            convertButton.isEnabled = false
            return
        }
        let mb = bytes / 1_048_576
        infoLabel.stringValue = String(
            format: L10n.tr("时长 %.1f 秒 · %d×%d · %.1f MB", "Duration %.1fs · %d×%d · %.1f MB"),
            duration, width, height, mb
        )
        convertButton.isEnabled = true
        updateOutLabel()
    }

    // MARK: 状态

    @objc private func settingsChanged() {
        guard job == nil else { return }
        updateOutLabel()
    }

    private func updateOutLabel() {
        guard let url = sourceURL, metaDuration > 0, metaW > 0 else { return }
        guard let plan = currentPlan() else { return }
        var text = String(
            format: L10n.tr("输出:%@ · %d 帧 · %d×%d", "Output: %@ · %d frames · %d×%d"),
            GifEncodePlan.gifFileName(forVideoName: url.lastPathComponent),
            plan.frameCount, plan.outW, plan.outH
        )
        if plan.frameCount > 1200 {
            text += L10n.tr(" · ⚠️ 帧数较多,GIF 体积会较大", " · ⚠️ Many frames, GIF will be large")
        }
        outLabel.stringValue = text
    }

    private func currentPlan() -> GifEncodePlan? {
        guard metaDuration > 0, metaW > 0, metaH > 0 else { return nil }
        let fps = fpsChoices[fpsPopup.indexOfSelectedItem]
        let maxW = widthChoices[widthPopup.indexOfSelectedItem]
        return GifEncodePlan(fps: fps, maxWidth: maxW, sourceW: metaW, sourceH: metaH, duration: metaDuration)
    }

    private func setConverting(_ on: Bool) {
        fpsPopup.isEnabled = !on
        widthPopup.isEnabled = !on
        setConvertTitle(on ? L10n.tr("取消转换", "Cancel") : L10n.tr("开始转换", "Convert to GIF"))
        progress.isHidden = !on
        if !on { progress.doubleValue = 0 }
    }

    /// 主按钮用 attributedTitle 承载白字，改文案时必须同步，否则视觉不更新
    private func setConvertTitle(_ title: String) {
        convertButton.title = title
        convertButton.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: UIStyle.Text.body(.medium),
            .foregroundColor: NSColor.white,
        ])
    }

    // MARK: 动作

    @objc private func convertClicked() {
        if job != nil {
            job?.cancel()
            return
        }
        startConvert()
    }

    private func startConvert() {
        guard let url = sourceURL, let plan = currentPlan() else { return }
        // 记住上次设置,下次打开面板沿用
        var cfg = AppConfig.load()
        cfg.recording.gifFps = fpsChoices[fpsPopup.indexOfSelectedItem]
        cfg.recording.gifMaxWidth = widthChoices[widthPopup.indexOfSelectedItem]
        cfg.write()

        let destURL = Self.makeDestURL(for: url)
        let j = GifEncodeJob(sourceURL: url, destURL: destURL, plan: plan)
        j.onProgress = { [weak self] done, total in
            guard let self, self.job === j else { return }
            self.progress.doubleValue = Double(done) / Double(max(1, total))
            self.statusLabel.stringValue = String(
                format: L10n.tr("转换中 %d/%d 帧…", "Converting %d/%d frames…"), done, total
            )
        }
        j.onOutcome = { [weak self] outcome in
            guard let self, self.job === j else { return }
            self.handleOutcome(outcome)
        }
        job = j
        setConverting(true)
        statusLabel.stringValue = L10n.tr("准备转换…", "Preparing…")
        j.start()
    }

    private func handleOutcome(_ outcome: GifEncodeJob.Outcome) {
        job = nil
        setConverting(false)
        switch outcome {
        case .saved(let url):
            statusLabel.stringValue = L10n.tr("已保存", "Saved")
            window?.orderOut(nil)
            // 直接弹 Quick Look 播放动画,避免用户去 Finder 双击后被「预览」静态打开
            if !QuickLookPreviewWindow.shared.preview(url) {
                // 预览窗不可用时降级:提示 + 在 Finder 中选中
                if let s = NSScreen.main {
                    ToastWindow.show(
                        text: L10n.tr("已保存 GIF", "GIF Saved"),
                        at: NSPoint(x: s.frame.midX, y: s.frame.midY)
                    )
                }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case .cancelled:
            statusLabel.stringValue = L10n.tr("已取消", "Cancelled")
        case .failed(let msg):
            statusLabel.stringValue = L10n.tr("失败", "Failed")
            let alert = NSAlert()
            alert.messageText = L10n.tr("转 GIF 失败", "GIF Conversion Failed")
            alert.informativeText = msg
            alert.alertStyle = .warning
            alert.addButton(withTitle: "好的")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func closeClicked() {
        window?.performClose(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 转换中关窗 = 取消任务,避免留下半成品或孤儿任务
        job?.cancel()
        return true
    }

    /// 输出到视频同目录,重名自动加序号
    private static func makeDestURL(for sourceURL: URL) -> URL {
        let dir = sourceURL.deletingLastPathComponent()
        let name = GifEncodePlan.gifFileName(forVideoName: sourceURL.lastPathComponent)
        var url = dir.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let base = (name as NSString).deletingPathExtension
            url = dir.appendingPathComponent("\(base) \(n).gif")
            n += 1
            if n > 99 { break }
        }
        return url
    }
}
