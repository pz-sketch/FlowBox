import AppKit
import os
import SharedCore

// MARK: - 诊断日志

func shotDebugLog(_ message: String) {
    FlowLog.screenshot.debug("\(message, privacy: .public)")
    let url = URL(fileURLWithPath: "/tmp/flowbox-shot-debug.log")
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

// MARK: - 十六进制颜色

extension NSColor {
    /// "#RRGGBB" → NSColor
    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// NSColor → "#RRGGBB"
    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#FF3B30" }
        return String(
            format: "#%02X%02X%02X",
            Int(round(c.redComponent * 255)),
            Int(round(c.greenComponent * 255)),
            Int(round(c.blueComponent * 255))
        )
    }
}

// MARK: - 截屏会话

/// 一次截屏会话:抓全屏快照 → 透明窗口冻结屏幕 → 框选 → 画笔/马赛克 → 复制/保存
final class ScreenshotSession: NSObject {

    static private(set) var isActive = false
    /// 持有当前会话(视图/工具条都只弱引用会话)
    static private var current: ScreenshotSession?

    private let config: ScreenshotConfig
    private var overlays: [OverlayWindow] = []
    private var activeOverlay: OverlayView?
    private var keyMonitor: Any?

    private init(config: ScreenshotConfig) {
        self.config = config
        super.init()
    }

    // MARK: 启动

    static func launch(initialTool: OverlayView.Tool? = nil) {
        guard !isActive else {
            FlowLog.screenshot.info("截图请求被忽略:已有会话进行中")
            return
        }
        // 屏幕录制权限:未授权时先触发系统弹窗,再引导到设置
        if !PermissionManager.isScreenCaptureTrusted {
            // 先弹系统授权框(真正的 TCC 弹窗),再给一个去重引导
            FlowLog.permission.info("截图:屏幕录制权限未授权,触发授权弹窗")
            PermissionManager.requestScreenCapture()
            // 异步轮询避免阻塞主线程;1.5s 内若授权则提示重启
            DispatchQueue.global(qos: .userInitiated).async {
                var granted = false
                for _ in 0..<6 {
                    Thread.sleep(forTimeInterval: 0.25)
                    if PermissionManager.isScreenCaptureTrusted { granted = true; break }
                }
                DispatchQueue.main.async {
                    if granted {
                        FlowLog.permission.info("截图:检测到用户已授权,提示重启")
                        let alert = NSAlert()
                        alert.messageText = L10n.tr("已授权,请重启 FlowBox", "Permission Granted — Restart Required")
                        alert.informativeText = L10n.tr("屏幕录制已允许,需退出并重新打开 FlowBox 后截图才生效(系统限制,本进程需重建才能抓屏)。", "Screen Recording is allowed. Please quit and reopen FlowBox for it to take effect (system limitation).")
                        alert.addButton(withTitle: L10n.tr("现在退出", "Quit Now"))
                        alert.addButton(withTitle: L10n.tr("稍后", "Later"))
                        NSApp.activate(ignoringOtherApps: true)
                        if alert.runModal() == .alertFirstButtonReturn { NSApp.terminate(nil) }
                        return
                    }
                    let alert = NSAlert()
                    alert.messageText = L10n.tr("需要「屏幕录制」权限", "Screen Recording Permission Required")
                    alert.informativeText = L10n.tr("""
                    截屏前,请到 系统设置 → 隐私与安全性 → 屏幕录制 中允许「FlowBox」,
                    然后退出本应用(菜单栏图标 → 退出)并重新打开,再按快捷键即可。
                    (若列表里已是打开状态,先关掉再打开)
                    """ , """
                    Before capturing, allow FlowBox in System Settings → Privacy & Security → Screen Recording,
                    then quit (menu bar → Quit) and reopen the app.
                    (If already on, toggle it off and on again.)
                    """)
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: L10n.tr("打开系统设置", "Open System Settings"))
                    alert.addButton(withTitle: L10n.tr("取消", "Cancel"))
                    NSApp.activate(ignoringOtherApps: true)
                    if alert.runModal() == .alertFirstButtonReturn {
                        PermissionManager.openScreenCaptureSettings()
                    }
                }
            }
            return
        }

        // 先抓所有屏幕的快照,再用覆盖窗口把画面「冻住」
        var captured: [(screen: NSScreen, image: CGImage)] = []
        var failedScreens: [String] = []
        FlowLog.screenshot.info("开始抓屏,屏幕数=\(NSScreen.screens.count, privacy: .public)")
        for screen in NSScreen.screens {
            guard
                let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                let image = CGDisplayCreateImage(id)
            else {
                let desc = "\(screen.frame) scale=\(screen.backingScaleFactor)"
                failedScreens.append(desc)
                FlowLog.screenshot.error("抓屏失败: \(desc, privacy: .public)")
                continue
            }
            if screen.safeAreaInsets.top > 0 {
                FlowLog.screenshot.debug("屏幕 \(String(describing: screen.frame), privacy: .public) 刘海 safeAreaTop=\(screen.safeAreaInsets.top)")
            }
            captured.append((screen, image))
        }
        guard !captured.isEmpty else {
            FlowLog.screenshot.error("全部屏幕抓取失败,失败列表: \(failedScreens.joined(separator: "; "), privacy: .public)")
            let alert = NSAlert()
            alert.messageText = L10n.tr("截屏失败", "Screenshot Failed")
            alert.informativeText = L10n.tr("无法抓取屏幕画面。若刚授权过「屏幕录制」,请退出并重新打开「FlowBox」后再试。", "Cannot capture screen. If you just granted Screen Recording, please quit and reopen FlowBox.")
            alert.addButton(withTitle: L10n.tr("好的", "OK"))
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            return
        }
        if !failedScreens.isEmpty {
            FlowLog.screenshot.info("部分屏幕抓取失败,但继续: 成功\(captured.count) 失败\(failedScreens.count)")
        }

        let session = ScreenshotSession(config: AppConfig.load().screenshot)
        session.begin(with: captured, initialTool: initialTool)
    }

    private func begin(with captured: [(screen: NSScreen, image: CGImage)], initialTool: OverlayView.Tool? = nil) {
        shotDebugLog("会话开始,屏幕数=\(captured.count)")
        ScreenshotSession.isActive = true
        ScreenshotSession.current = self

        NSApp.activate(ignoringOtherApps: true)
        for item in captured {
            let overlay = OverlayWindow(screen: item.screen, image: item.image, session: self)
            overlay.orderFront(nil)
            overlays.append(overlay)
        }

        // 鼠标所在屏幕的浮层成为按键窗口,接收键盘事件
        let mouse = NSEvent.mouseLocation
        let target = overlays.first(where: { $0.screenFrame.contains(mouse) }) ?? overlays.first
        target?.makeKeyAndOrderFront(nil)
        activeOverlay = target?.overlayView
        if let tool = initialTool {
            activeOverlay?.tool = tool
        }

        NSSound(named: NSSound.Name("Tink"))?.play()

        // 双屏同时显示十字光标: push 在失去 key 时会被系统重置，改用 set 并在进入时刷新
        NSCursor.crosshair.set()
        DispatchQueue.main.async {
            NSCursor.crosshair.set()
            // 强制系统重算 cursorRects
            for ov in self.overlays { ov.overlayView.window?.invalidateCursorRects(for: ov.overlayView) }
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // 文字输入中,Enter/Esc 交给输入框处理
        if activeOverlay?.isTextInputActive == true { return event }
        switch event.keyCode {
        case 53: // Esc
            cancel()
            return nil
        case 36, 76: // Return / 小键盘 Enter
            finishCopy()
            return nil
        case 6 where event.modifierFlags.contains(.command): // ⌘Z
            undo()
            return nil
        case 1 where event.modifierFlags.contains(.command): // ⌘S
            saveToDesktop()
            return nil
        default:
            return event
        }
    }

    // MARK: 结束

    @objc func cancel() {
        shotDebugLog("会话取消")
        close()
    }

    private func close() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        NSCursor.arrow.set()
        for overlay in overlays { overlay.orderOut(nil) }
        overlays.removeAll()
        activeOverlay = nil
        ScreenshotSession.isActive = false
        ScreenshotSession.current = nil
    }

    /// 选区(含标注)渲染为 PNG 并复制到剪贴板
    @objc func finishCopy() {
        guard let view = activeOverlay, let sel = view.selectionRect,
              let png = view.renderCropPNG() else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        let center = screenPoint(of: view, viewPoint: NSPoint(x: sel.midX, y: sel.midY))
        close()
        ToastWindow.show(text: L10n.tr("已复制到剪贴板", "Copied to Clipboard"), at: center)
        NSLog("[FlowBox] 截图:已复制 \(Int(sel.width))x\(Int(sel.height))")
    }

    /// 选区(含标注)保存为桌面上的 PNG 文件
    @objc func saveToDesktop() {
        guard let view = activeOverlay, let sel = view.selectionRect,
              let png = view.renderCropPNG() else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmmss"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("截屏 \(formatter.string(from: Date())).png")
        do {
            try png.write(to: url)
            let center = screenPoint(of: view, viewPoint: NSPoint(x: sel.midX, y: sel.midY))
            close()
            NSWorkspace.shared.activateFileViewerSelecting([url])
            ToastWindow.show(text: L10n.tr("已保存到桌面", "Saved to Desktop"), at: center)
            NSLog("[FlowBox] 截图:已保存 \(url.path)")
        } catch {
            NSLog("[FlowBox] 截图保存失败: \(error.localizedDescription)")
            ToastWindow.show(text: L10n.tr("保存失败：\(error.localizedDescription)", "Save failed: \(error.localizedDescription)"), at: screenPoint(of: view, viewPoint: NSPoint(x: sel.midX, y: sel.midY)))
        }
    }

    @objc func undo() {
        activeOverlay?.undoStroke()
    }

    /// 工具条按钮入口(视图内自绘工具条直接调用)
    @objc func selectPen() { setTool(.pen) }
    @objc func selectMosaic() { setTool(.mosaic) }
    @objc func selectText() { setTool(.text) }
    @objc func selectRect() { setTool(.rect) }
    @objc func selectEllipse() { setTool(.ellipse) }

    func setTool(_ tool: OverlayView.Tool) {
        // 切走文字工具时,未确认的输入直接丢弃
        activeOverlay?.discardTextInput()
        activeOverlay?.tool = tool
    }

    func setActiveOverlay(_ view: OverlayView) {
        activeOverlay = view
    }

    /// 视图坐标 → 屏幕全局坐标(AppKit 底左原点)
    private func screenPoint(of view: NSView, viewPoint: NSPoint) -> NSPoint {
        guard let window = view.window else { return viewPoint }
        let inWindow = view.convert(viewPoint, to: nil)
        return window.convertToScreen(NSRect(origin: inWindow, size: .zero)).origin
    }
}

// MARK: - 结果提示

/// 自动消失的小提示条
final class ToastWindow: NSPanel {

    static func show(text: String, at center: NSPoint) {
        let font = UIStyle.Text.body(.medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let padding: CGFloat = 18
        let boxW = textSize.width + padding * 2
        let boxH = textSize.height + 14

        let container = NSView(frame: NSRect(x: 0, y: 0, width: boxW, height: boxH))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.76).cgColor
        container.layer?.cornerRadius = UIStyle.Metrics.radiusM
        container.layer?.cornerCurve = .continuous
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .white
        label.frame = NSRect(
            x: padding,
            y: (boxH - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        container.addSubview(label)

        let window = ToastWindow(
            contentRect: NSRect(x: center.x - boxW / 2, y: center.y - boxH / 2, width: boxW, height: boxH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = container
        window.alphaValue = 0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            NSAnimationContext.runAnimationGroup(
                { context in
                    context.duration = 0.3
                    window.animator().alphaValue = 0
                },
                completionHandler: { window.orderOut(nil) }
            )
        }
    }

    override var canBecomeKey: Bool { false }
}

// MARK: - 覆盖窗口

/// 全屏无边框覆盖窗口(可成为按键窗口以接收键盘)
final class OverlayWindow: NSWindow {

    let screenFrame: CGRect
    let overlayView: OverlayView

    init(screen: NSScreen, image: CGImage, session: ScreenshotSession) {
        let frame = screen.frame
        let view = OverlayView(
            frame: NSRect(origin: .zero, size: frame.size),
            screenFrame: frame,
            image: image,
            session: session
        )
        self.screenFrame = frame
        self.overlayView = view
        // 必须用末端 designated 构造器(不带 screen:):带 screen: 的版本内部会
        // 回调 self 的 init(contentRect:...) 派发到子类合成实现,触发运行时崩溃
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = view
    }

    required init?(coder: NSCoder) { fatalError("不支持从 NSCoder 初始化") }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 覆盖视图(框选 + 标注)

final class OverlayView: NSView {

    enum Phase { case idle, selecting, annotating, moving }
    enum Tool { case pen, mosaic, text, rect, ellipse }

    /// 一笔:折线点集 + 工具参数(坐标为视图顶左坐标系)
    struct Stroke {
        let tool: Tool
        var points: [CGPoint]
        let width: CGFloat
        let color: CGColor
        var text: String? = nil
        var fontSize: CGFloat = 0
    }

    /// 文字工具单行字号
    static let textFontSize: CGFloat = 18

    let screenFrame: CGRect
    private let bgImage: CGImage
    private let pixelatedImage: CGImage?
    private let penColor: NSColor
    private let penWidth: CGFloat
    private weak var session: ScreenshotSession?

    private(set) var phase: Phase = .idle
    var tool: Tool? = nil
    private(set) var selectionRect: CGRect?
    private(set) var strokes: [Stroke] = []
    private var currentStroke: Stroke?
    private var dragStart: CGPoint = .zero
    /// 拖动移动选区:按下时的鼠标点与起始快照,拖拽中按「总位移」平移
    /// (用快照而非增量累加,避免多次拖拽累积浮点误差)
    private var moveStartPoint: CGPoint = .zero
    private var moveOriginRect: CGRect = .zero
    private var moveOriginStrokes: [Stroke] = []
    /// 文字输入浮层(存在时=正在输入)
    private var textInput: TextInputField?
    var isTextInputActive: Bool { textInput != nil }
    /// 本轮鼠标交互始于工具条(拖拽/抬起不再当作画笔)
    private var toolbarDrag = false
    /// 马赛克刷头跟随鼠标的位置(用于绘制圆圈预览)
    private var mosaicPreviewPoint: CGPoint?

    // MARK: 自绘工具条

    /// 工具条按钮(绘制与点击命中共用同一布局)
    enum ToolbarAction {
        case pen, mosaic, text, rect, ellipse, ocr, undo, save, copy, confirm, cancel

        var title: String {
            switch self {
            case .pen: return L10n.tr("画笔", "Pen")
            case .mosaic: return L10n.tr("马赛克", "Mosaic")
            case .text: return L10n.tr("文字", "Text")
            case .rect: return L10n.tr("矩形", "Rectangle")
            case .ellipse: return L10n.tr("椭圆", "Ellipse")
            case .ocr: return L10n.tr("识别", "OCR")
            case .undo: return L10n.tr("撤销", "Undo")
            case .save: return L10n.tr("保存", "Save")
            case .copy: return L10n.tr("复制", "Copy")
            case .confirm: return L10n.tr("确认", "Done")
            case .cancel: return L10n.tr("取消", "Cancel")
            }
        }

        var symbolName: String {
            switch self {
            case .pen: return "pencil"
            case .mosaic: return "checkerboard.rectangle"
            case .text: return "t.square"
            case .rect: return "rectangle"
            case .ellipse: return "oval"
            case .ocr: return "doc.text.magnifyingglass"
            case .undo: return "arrow.uturn.backward"
            case .save: return "square.and.arrow.down"
            case .copy: return "doc.on.clipboard"
            case .confirm: return "checkmark"
            case .cancel: return "xmark"
            }
        }
    }

    private static let toolbarFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    /// 由当前选区计算工具条布局(选区下方,放不下移到上方)
    /// 返回:面板 rect(相对 view 原点的绝对坐标)、按钮在 view 坐标系中的 rect 列表
    private func toolbarLayout() -> (rect: CGRect, buttons: [(action: ToolbarAction, rect: CGRect)])? {
        guard let sel = selectionRect, sel.width >= 8, sel.height >= 8 else { return nil }
        let order: [ToolbarAction] = [.pen, .rect, .ellipse, .mosaic, .text, .ocr, .undo, .save, .copy, .confirm, .cancel]
        let pad: CGFloat = 8, innerGap: CGFloat = 2, outerGap: CGFloat = 6, bh: CGFloat = 28
        let panelH: CGFloat = bh + pad * 2
        // 紧凑图标按钮；标题保留为 tooltip/accessibility 文案
        let groupSet: Set<ToolbarAction> = [.pen, .rect, .ellipse]
        var total: CGFloat = pad
        for (idx, action) in order.enumerated() {
            total += 30
            if idx < order.count - 1 {
                let next = order[idx + 1]
                total += (groupSet.contains(action) && groupSet.contains(next)) ? innerGap : outerGap
            }
        }
        total += pad
        // 刘海避让:顶部 safeAreaInset 区域不放工具条
        let topInset: CGFloat
        if let screen = window?.screen {
            topInset = screen.safeAreaInsets.top
        } else {
            topInset = 0
        }
        let availableTop = bounds.height - topInset - 4
        let origin = CGPoint(
            x: max(4, min(bounds.width - total - 4, sel.midX - total / 2)),
            y: sel.maxY + 10 > availableTop - panelH
                ? sel.minY - 10 - panelH
                : sel.maxY + 10
        )
        let tbRect = CGRect(origin: origin, size: CGSize(width: total, height: panelH))
        var x = pad
        var buttons: [(action: ToolbarAction, rect: CGRect)] = []
        for (idx, action) in order.enumerated() {
            let w: CGFloat = 30
            buttons.append((action, CGRect(x: origin.x + x, y: origin.y + pad, width: w, height: bh)))
            if idx < order.count - 1 {
                let next = order[idx + 1]
                let g: CGFloat = (groupSet.contains(action) && groupSet.contains(next)) ? innerGap : outerGap
                x += w + g
            }
        }
        return (tbRect, buttons)
    }

    private var isOCRing = false

    private func performToolbar(_ action: ToolbarAction) {
        shotDebugLog("工具条点击: \(action.title)")
        FlowLog.screenshot.info("工具条点击: \(action.title, privacy: .public)")
        switch action {
        case .pen: session?.selectPen()
        case .mosaic: session?.selectMosaic()
        case .text: session?.selectText()
        case .rect: session?.selectRect()
        case .ellipse: session?.selectEllipse()
        case .ocr: runOCR()
        case .undo: session?.undo()
        case .save: session?.saveToDesktop()
        case .copy: session?.finishCopy()
        case .confirm: session?.finishCopy()
        case .cancel: session?.cancel()
        }
        needsDisplay = true
    }

    /// 选区背景原图(不含标注/边框),用于 OCR
    private func croppedBackgroundCGImage() -> CGImage? {
        guard let sel = selectionRect else { return nil }
        let scale = CGFloat(bgImage.width) / bounds.width
        let pw = max(1, Int((sel.width * scale).rounded()))
        let ph = max(1, Int((sel.height * scale).rounded()))
        let colorSpace = bgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.setAllowsAntialiasing(true)
        // 与 renderCropPNG 保持一致的翻转变换
        ctx.translateBy(x: 0, y: CGFloat(ph))
        ctx.scaleBy(x: scale, y: -scale)
        ctx.translateBy(x: -sel.minX, y: -sel.minY)
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        // 仅画背景,不含 chrome 与标注
        ctx.saveGState()
        ctx.translateBy(x: bounds.minX, y: bounds.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(bgImage, in: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
        ctx.restoreGState()
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// 识别当前选区的文字:后台 Vision 识别 → 复制+可编辑浮层展示
    private func runOCR() {
        guard !isOCRing else { return }
        guard let sel = selectionRect, sel.width >= 8, sel.height >= 8 else {
            ToastWindow.show(text: L10n.tr("请先框选区域", "Select an area first"), at: NSPoint(x: bounds.midX, y: bounds.midY))
            return
        }
        guard let image = croppedBackgroundCGImage() else {
            ToastWindow.show(text: L10n.tr("识别失败:无法获取图像", "OCR failed: no image"), at: NSPoint(x: sel.midX, y: sel.midY))
            return
        }
        isOCRing = true
        needsDisplay = true
        let anchor = NSPoint(x: sel.midX, y: sel.midY)
        let screenCenter: NSPoint = {
            guard let w = window else { return anchor }
            let inWindow = convert(anchor, to: nil)
            return w.convertToScreen(NSRect(origin: inWindow, size: .zero)).origin
        }()
        ToastWindow.show(text: L10n.tr("识别中…", "Recognizing…"), at: screenCenter)
        OCRService.recognize(cgImage: image) { [weak self] result in
            guard let self else { return }
            self.isOCRing = false
            self.needsDisplay = true
            switch result {
            case .success(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    ToastWindow.show(text: L10n.tr("未识别到文字", "No text found"), at: screenCenter)
                    return
                }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(trimmed, forType: .string)
                OCRResultWindow.show(text: trimmed, at: screenCenter)
            case .failure(let error):
                ToastWindow.show(text: L10n.tr("识别失败: \(error.localizedDescription)", "OCR failed: \(error.localizedDescription)"), at: screenCenter)
            }
        }
    }

    init(frame: NSRect, screenFrame: CGRect, image: CGImage, session: ScreenshotSession) {
        let cfg = AppConfig.load().screenshot
        self.screenFrame = screenFrame
        self.bgImage = image
        self.session = session
        self.penColor = NSColor(hexString: cfg.penColorHex) ?? NSColor.systemRed
        self.penWidth = CGFloat(cfg.penWidth)
        self.pixelatedImage = OverlayView.pixelated(image: image, block: CGFloat(cfg.mosaicBlock))
        shotDebugLog("覆盖视图初始化: pixelated=\(self.pixelatedImage != nil ? "OK" : "NIL!") block=\(Int(cfg.mosaicBlock)) bgPx=\(image.width)x\(image.height)")
        if self.pixelatedImage == nil {
            FlowLog.screenshot.error("马赛克预生成失败 block=\(Int(cfg.mosaicBlock))")
        }
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(L10n.tr("截屏覆盖层", "Screenshot overlay"))
        setAccessibilityHelp(L10n.tr("拖动框选区域，使用工具条进行标注或输出", "Drag to select an area, then use the toolbar to annotate or export"))
    }

    required init?(coder: NSCoder) { fatalError("不支持从 NSCoder 初始化") }

    override var isFlipped: Bool { true }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.invalidateCursorRects(for: self) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var trackingArea: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    private func updateCursor(at p: NSPoint) {
        if let (tbRect, buttons) = toolbarLayout() {
            if buttons.contains(where: { $0.rect.contains(p) }) {
                NSCursor.pointingHand.set()
                return
            }
            if tbRect.contains(p) {
                NSCursor.arrow.set()
                return
            }
        }
        if let sel = selectionRect, sel.width >= 8, sel.height >= 8 {
            if sel.contains(p) {
                if phase == .moving {
                    NSCursor.closedHand.set()  // 拖动中:抓紧
                } else if canMoveSelection {
                    NSCursor.openHand.set()  // 可拖动移动选区
                } else {
                    NSCursor.crosshair.set()  // 已选工具:在选区内落笔
                }
            } else {
                NSCursor.arrow.set()
            }
            return
        }
        NSCursor.crosshair.set()
    }

    /// 当前是否处于「拖动移动选区」手势:未选工具,或按住 ⌥ 强制移动(选了工具也能挪框)
    private var canMoveSelection: Bool {
        tool == nil || NSEvent.modifierFlags.contains(.option)
    }

    override func mouseEntered(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        updateCursor(at: p)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        updateCursor(at: p)
        guard tool == .mosaic, phase == .annotating, selectionRect != nil, currentStroke == nil else {
            if mosaicPreviewPoint != nil { mosaicPreviewPoint = nil; needsDisplay = true }
            return
        }
        if let sel = selectionRect, sel.contains(p), toolbarLayout()?.rect.contains(p) != true {
            mosaicPreviewPoint = p
        } else {
            mosaicPreviewPoint = nil
        }
        needsDisplay = true
    }

    override func resetCursorRects() {
        discardCursorRects()
        if let sel = selectionRect, sel.width >= 8, sel.height >= 8 {
            if let (tbRect, buttons) = toolbarLayout() {
                addCursorRect(tbRect, cursor: .arrow)
                for b in buttons { addCursorRect(b.rect, cursor: .pointingHand) }
            }
            addCursorRect(sel, cursor: canMoveSelection ? .openHand : .crosshair)
            if sel.minY > 0 {
                addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: sel.minY), cursor: .arrow)
            }
            if sel.maxY < bounds.height {
                addCursorRect(NSRect(x: 0, y: sel.maxY, width: bounds.width, height: bounds.height - sel.maxY), cursor: .arrow)
            }
            if sel.minX > 0 {
                addCursorRect(NSRect(x: 0, y: sel.minY, width: sel.minX, height: sel.height), cursor: .arrow)
            }
            if sel.maxX < bounds.width {
                addCursorRect(NSRect(x: sel.maxX, y: sel.minY, width: bounds.width - sel.maxX, height: sel.height), cursor: .arrow)
            }
        } else {
            if let (tbRect, buttons) = toolbarLayout() {
                addCursorRect(tbRect, cursor: .arrow)
                for b in buttons { addCursorRect(b.rect, cursor: .pointingHand) }
                addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: tbRect.minY), cursor: .crosshair)
                addCursorRect(NSRect(x: 0, y: tbRect.maxY, width: bounds.width, height: bounds.height - tbRect.maxY), cursor: .crosshair)
                addCursorRect(NSRect(x: 0, y: tbRect.minY, width: tbRect.minX, height: tbRect.height), cursor: .crosshair)
                addCursorRect(NSRect(x: tbRect.maxX, y: tbRect.minY, width: bounds.width - tbRect.maxX, height: tbRect.height), cursor: .crosshair)
            } else {
                addCursorRect(bounds, cursor: .crosshair)
            }
        }
    }

    // MARK: 鼠标

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        session?.setActiveOverlay(self)
        toolbarDrag = false
        // 正在输入文字时,点击别处 = 确认当前文字(继续处理本次点击)
        if let input = textInput {
            _ = input.confirmIfNeeded(clickPoint: p)
        }
        // 工具条点击
        if let (tbRect, buttons) = toolbarLayout(), tbRect.contains(p) {
            toolbarDrag = true
            if let hit = buttons.first(where: { $0.rect.contains(p) }) {
                performToolbar(hit.action)
            }
            return
        }
        if let sel = selectionRect, sel.insetBy(dx: -4, dy: -4).contains(p) {
            // 未选工具(或按住 ⌥)时,在选区内拖动 = 平移整个选区,标注随之移动
            if canMoveSelection {
                beginMovingSelection(at: p, from: sel)
                return
            }
            guard let currentTool = tool else { return }
            if currentTool == .text {
                beginTextInput(at: p)
                needsDisplay = true
                return
            }
            // 选区内落笔
            phase = .annotating
            currentStroke = makeStroke(start: p)
        } else {
            // 选区外重新框选(丢弃旧选区与标注)
            phase = .selecting
            dragStart = p
            selectionRect = nil
            strokes.removeAll()
            currentStroke = nil
            endTextInput(confirm: false)
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        // 右键随时退出截屏,避免盖住菜单栏导致无法操作
        shotDebugLog("右键取消")
        session?.cancel()
    }

    override func otherMouseDown(with event: NSEvent) {
        shotDebugLog("中键取消")
        session?.cancel()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !toolbarDrag else { return }
        let p = convert(event.locationInWindow, from: nil)
        switch phase {
        case .selecting:
            selectionRect = rect(between: dragStart, and: p)
            window?.invalidateCursorRects(for: self)
        case .annotating:
            if isShapeTool {
                guard var s = currentStroke, s.points.count >= 2 else { break }
                s.points[1] = adjustedShapeEnd(from: s.points[0], to: p, event: event)
                currentStroke = s
            } else {
                currentStroke?.points.append(p)
            }
        case .moving:
            applySelectionMove(to: p)
            updateCursor(at: p)  // 拖动过程中保持「抓紧」光标
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if toolbarDrag {
            toolbarDrag = false
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        switch phase {
        case .selecting:
            if let sel = selectionRect, sel.width >= 8, sel.height >= 8 {
                phase = .annotating
                let name: String = {
                    switch tool {
                    case .pen: return "画笔"
                    case .mosaic: return "马赛克"
                    case .text: return "文字"
                    case .rect: return "矩形"
                    case .ellipse: return "椭圆"
                    case nil: return "未选"
                    }
                }()
                shotDebugLog("框选完成: \(Int(sel.width))x\(Int(sel.height)) 工具=\(name)")
            } else {
                selectionRect = nil
                phase = .idle
            }
            window?.invalidateCursorRects(for: self)
        case .annotating:
            if var stroke = currentStroke {
                if isShapeTool {
                    stroke.points[1] = adjustedShapeEnd(from: stroke.points[0], to: p, event: event)
                    // 过小拖拽不落笔
                    if abs(stroke.points[1].x - stroke.points[0].x) < 4 || abs(stroke.points[1].y - stroke.points[0].y) < 4 {
                        currentStroke = nil
                        needsDisplay = true
                        return
                    }
                } else {
                    stroke.points.append(p)
                }
                strokes.append(stroke)
                let name: String = {
                    switch stroke.tool {
                    case .pen: return "画笔"
                    case .mosaic: return "马赛克"
                    case .text: return "文字"
                    case .rect: return "矩形"
                    case .ellipse: return "椭圆"
                    }
                }()
                shotDebugLog("一笔完成: tool=\(name) 点数=\(stroke.points.count) 宽=\(Int(stroke.width))")
            }
            currentStroke = nil
        case .moving:
            // 选区已确认,回到标注态(与框选结束一致)
            phase = .annotating
            if let sel = selectionRect {
                shotDebugLog("移动选区至 (\(Int(sel.minX)), \(Int(sel.minY))) 尺寸 \(Int(sel.width))x\(Int(sel.height))")
            }
            window?.invalidateCursorRects(for: self)
        default:
            break
        }
        needsDisplay = true
    }

    // MARK: 拖动移动选区

    /// 进入拖动移动:记录起点与快照,标注一并平移
    /// (导出时按选区原点裁切,标注不同步就会错位)
    private func beginMovingSelection(at p: CGPoint, from rect: CGRect) {
        endTextInput(confirm: true)  // 正在输入文字则先落笔,避免浮层留在原地
        phase = .moving
        moveStartPoint = p
        moveOriginRect = rect
        moveOriginStrokes = strokes
        currentStroke = nil
        NSCursor.closedHand.set()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    /// 按鼠标总位移平移选区与全部标注,并夹在屏幕内
    private func applySelectionMove(to p: CGPoint) {
        guard phase == .moving else { return }
        let delta = SelectionGeometry.clampedDelta(
            rect: moveOriginRect,
            bounds: bounds,
            dx: p.x - moveStartPoint.x,
            dy: p.y - moveStartPoint.y
        )
        let newRect = SelectionGeometry.offset(moveOriginRect, by: delta)
        guard newRect != selectionRect else { return }  // 无实际位移则不重绘
        selectionRect = newRect
        strokes = moveOriginStrokes.map { stroke in
            var moved = stroke
            moved.points = SelectionGeometry.offset(stroke.points, by: delta)
            return moved
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func undoStroke() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        needsDisplay = true
    }

    private func makeStroke(start: CGPoint) -> Stroke {
        switch tool! {
        case .pen:
            return Stroke(tool: .pen, points: [start], width: penWidth, color: penColor.cgColor)
        case .mosaic:
            // 马赛克笔刷较宽(画笔宽度的 5 倍,至少 20pt),色值仅占位(实际贴像素化图)
            return Stroke(tool: .mosaic, points: [start], width: max(20, penWidth * 5), color: NSColor.black.cgColor)
        case .text:
            return Stroke(tool: .text, points: [start], width: 0, color: penColor.cgColor,
                          text: "", fontSize: OverlayView.textFontSize)
        case .rect, .ellipse:
            return Stroke(tool: tool!, points: [start, start], width: max(2, penWidth), color: penColor.cgColor)
        }
    }

    /// 是否形状工具(矩形/椭圆):拖拽为对角两点,不追加折线点
    private var isShapeTool: Bool { tool == .rect || tool == .ellipse }

    /// 按当前按下的修饰键约束形状(Shift = 正方形/正圆)
    private func adjustedShapeEnd(from start: CGPoint, to end: CGPoint, event: NSEvent?) -> CGPoint {
        guard let e = event, e.modifierFlags.contains(.shift) else { return end }
        var w = end.x - start.x
        var h = end.y - start.y
        let s = min(abs(w), abs(h))
        w = (w >= 0 ? s : -s)
        h = (h >= 0 ? s : -s)
        return CGPoint(x: start.x + w, y: start.y + h)
    }

    private func shapeRect(for stroke: Stroke) -> CGRect? {
        guard stroke.points.count >= 2 else { return nil }
        let a = stroke.points[0], b = stroke.points[1]
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: 文字输入

    /// 在点击处弹出单行文字输入浮层;Enter 确认生成文字笔画,Esc 丢弃
    private func beginTextInput(at point: CGPoint) {
        endTextInput(confirm: false)
        let field = TextInputField(
            frame: NSRect(x: point.x, y: point.y - 14, width: 260, height: 28),
            onComplete: { [weak self] text, origin in
                self?.finishTextInput(text: text, at: origin)
            },
            onCancel: { [weak self] in
                self?.endTextInput(confirm: false)
            }
        )
        field.font = NSFont.systemFont(ofSize: OverlayView.textFontSize, weight: .semibold)
        field.textColor = penColor
        field.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .exterior
        field.placeholderString = L10n.tr("输入文字，按 Enter 确认", "Type text, press Enter to confirm")
        field.setAccessibilityLabel(L10n.tr("文字标注输入框", "Annotation text field"))
        field.setAccessibilityHelp(L10n.tr("输入文字后按 Enter 确认，按 Esc 取消", "Press Enter to confirm or Esc to cancel"))
        addSubview(field)
        textInput = field
        window?.makeFirstResponder(field)
    }

    private func finishTextInput(text: String, at origin: CGPoint) {
        endTextInput(confirm: false)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        strokes.append(
            Stroke(tool: .text, points: [origin], width: 0, color: penColor.cgColor,
                   text: trimmed, fontSize: OverlayView.textFontSize)
        )
        shotDebugLog("文字标注: \"\(trimmed)\"")
        needsDisplay = true
    }

    private func endTextInput(confirm: Bool) {
        guard let field = textInput else { return }
        let text = field.stringValue
        let origin = NSPoint(x: field.frame.minX, y: field.frame.midY)
        textInput = nil
        field.removeFromSuperview()
        if confirm { finishTextInput(text: text, at: origin) }
        needsDisplay = true
    }

    /// 会话关闭前丢弃未确认的输入
    func discardTextInput() {
        endTextInput(confirm: false)
    }

    private func rect(between a: CGPoint, and b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: 绘制

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawScene(in: ctx, chrome: true)
    }

    /// 绘制背景与标注;chrome=true 时附加压暗遮罩、边框、提示等界面元素。
    /// 调用方须保证 ctx 为「顶左原点」坐标系(AppKit 翻转视图自带,导出时手动翻转)。
    private func drawScene(in ctx: CGContext, chrome: Bool) {
        drawBitmap(bgImage, in: bounds, ctx: ctx)

        if chrome, let sel = selectionRect {
            // 选区外压暗
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            ctx.addRect(bounds)
            ctx.addRect(sel)
            ctx.fillPath(using: .evenOdd)
        }

        // 标注笔画(只画在选区内)
        ctx.saveGState()
        if let sel = selectionRect {
            ctx.addRect(sel)
            ctx.clip()
        }
        for stroke in strokes { drawStroke(stroke, in: ctx) }
        if let s = currentStroke { drawStroke(s, in: ctx) }
        ctx.restoreGState()

        guard chrome else { return }

        if let sel = selectionRect {
            // 边框
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(sel)
            // 四角手柄
            let h: CGFloat = 8
            let corners = [
                sel.origin,
                CGPoint(x: sel.maxX, y: sel.minY),
                CGPoint(x: sel.minX, y: sel.maxY),
                CGPoint(x: sel.maxX, y: sel.maxY),
            ]
            for corner in corners {
                let r = CGRect(x: corner.x - h / 2, y: corner.y - h / 2, width: h, height: h)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(r)
                ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.45).cgColor)
                ctx.setLineWidth(1)
                ctx.stroke(r)
            }
            // 尺寸标签(选区上方,越界时移入选区内);未选工具时附带「可拖动」提示
            var text = L10n.tr("尺寸 \(Int(sel.width)) × \(Int(sel.height))", "Size \(Int(sel.width)) × \(Int(sel.height))")
            if tool == nil {
                text += L10n.tr("  ·  拖动可移动", "  ·  Drag to move")
            }
            drawLabel(text, at: NSPoint(x: sel.minX, y: max(4, sel.minY - 26)))
            // 工具条
            drawToolbar()
            // 马赛克刷头预览(鼠标处的圆圈,示意覆盖范围)
            drawMosaicPreview()
        } else if phase == .idle {
            // 刘海屏顶部避开 36pt 后字号放大,更醒目
            drawIdleHint(at: NSPoint(x: bounds.midX, y: 48))
        }
    }

    /// 在覆盖层内绘制工具条(选区下方,越界移到上方) — 亮色高对比方案
    private func drawToolbar() {
        guard let (tbRect, buttons) = toolbarLayout() else { return }
        // 亮色磨砂底板:白底高不透明 + 柔和投影,在压暗(0.35)背景上清晰可辨
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowOffset = NSSize(width: 0, height: 6)
        shadow.shadowBlurRadius = 16
        shadow.set()
        NSColor.white.withAlphaComponent(0.94).setFill()
        let bgPath = NSBezierPath(roundedRect: tbRect, xRadius: 11, yRadius: 11)
        bgPath.fill()
        NSGraphicsContext.restoreGraphicsState()
        // 双层细描边提升立体感
        NSColor.black.withAlphaComponent(0.10).setStroke()
        NSBezierPath(roundedRect: tbRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11).stroke()
        NSColor.white.withAlphaComponent(0.65).setStroke()
        NSBezierPath(roundedRect: tbRect.insetBy(dx: 1.5, dy: 1.5), xRadius: 10, yRadius: 10).stroke()

        // 绘图工具分组:浅灰 pill 底座 + 细分隔线
        if let firstIdx = buttons.firstIndex(where: { $0.0 == .pen }),
           let lastIdx = buttons.firstIndex(where: { $0.0 == .ellipse }),
           firstIdx < lastIdx {
            let firstR = buttons[firstIdx].1
            let lastR = buttons[lastIdx].1
            let groupRect = NSRect(x: firstR.minX - 4, y: firstR.minY - 4, width: lastR.maxX - firstR.minX + 8, height: firstR.height + 8)
            NSColor.black.withAlphaComponent(0.06).setFill()
            NSBezierPath(roundedRect: groupRect, xRadius: 8, yRadius: 8).fill()
            NSColor.black.withAlphaComponent(0.07).setStroke()
            NSBezierPath(roundedRect: groupRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8).stroke()
            for idx in [firstIdx + 1, lastIdx] {
                if idx <= lastIdx {
                    let rx = buttons[idx].1.minX - 2.5
                    NSColor.black.withAlphaComponent(0.10).setFill()
                    NSBezierPath(roundedRect: NSRect(x: rx, y: groupRect.midY - 8, width: 1, height: 16), xRadius: 0.5, yRadius: 0.5).fill()
                }
            }
        }
        // 按钮
        for (action, r) in buttons {
            let isActive = (action == .pen && tool == .pen)
                || (action == .mosaic && tool == .mosaic)
                || (action == .text && tool == .text)
                || (action == .rect && tool == .rect)
                || (action == .ellipse && tool == .ellipse)
            let isConfirm = action == .confirm
            let isOCR = action == .ocr
            let dimmed = (action == .undo && strokes.isEmpty) || (isOCR && isOCRing)

            // 选中态:用系统强调色浅底,比白底更醒目
            if isActive {
                NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).fill()
                NSColor.controlAccentColor.withAlphaComponent(0.22).setStroke()
                NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6).stroke()
            }
            if isConfirm {
                NSColor.systemGreen.withAlphaComponent(0.95).setFill()
                NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
            } else if action == .cancel {
                // 取消用浅灰底,避免与确认同权重
                NSColor.black.withAlphaComponent(0.06).setFill()
                NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
            } else if isOCR && isOCRing {
                NSColor.black.withAlphaComponent(0.06).setFill()
                NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
            }

            if let image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.title) {
                image.isTemplate = true
                let iconSize: CGFloat = 18
                let iconRect = NSRect(x: r.midX - iconSize / 2, y: r.midY - iconSize / 2, width: iconSize, height: iconSize)
                let iconColor: NSColor
                if isConfirm {
                    iconColor = NSColor.white.withAlphaComponent(dimmed ? 0.4 : 1)
                } else if isActive {
                    iconColor = NSColor.controlAccentColor.withAlphaComponent(dimmed ? 0.45 : 1)
                } else {
                    iconColor = NSColor.labelColor.withAlphaComponent(dimmed ? 0.32 : 0.88)
                }
                // isFlipped=true 的视图里直接 draw 会垂直镜像,checkmark 这类不对称符号会显成"反钩"
                // 用 respectFlipped:true 保证朝向正确;同时先 set 颜色让模板按该色着染
                NSGraphicsContext.saveGraphicsState()
                iconColor.set()
                image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
            }
            _ = action.title
        }
    }

    /// 绘制马赛克刷头预览圆圈(跟随鼠标)
    private func drawMosaicPreview() {
        guard tool == .mosaic, let p = mosaicPreviewPoint, phase == .annotating, currentStroke == nil else { return }
        let r = max(20, penWidth * 5) / 2
        NSColor.white.setStroke()
        let path = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        path.lineWidth = 1.5
        path.stroke()
        NSColor.black.withAlphaComponent(0.5).setStroke()
        let inner = NSBezierPath(ovalIn: NSRect(x: p.x - r + 0.5, y: p.y - r + 0.5, width: r * 2 - 1, height: r * 2 - 1))
        inner.lineWidth = 1
        inner.stroke()
    }

    /// 在顶左坐标系中正立绘制 CGImage
    private func drawBitmap(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    private func drawStroke(_ stroke: Stroke, in ctx: CGContext) {
        let pts = stroke.points
        guard let first = pts.first else { return }
        let path = CGMutablePath()
        path.move(to: first)
        if pts.count == 1 {
            // 单点:偏移半像素配合圆头画出圆点
            path.addLine(to: CGPoint(x: first.x + 0.5, y: first.y))
        } else {
            for p in pts.dropFirst() { path.addLine(to: p) }
        }
        ctx.saveGState()
        switch stroke.tool {
        case .pen:
            ctx.addPath(path)
            ctx.setStrokeColor(stroke.color)
            ctx.setLineWidth(stroke.width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokePath()
        case .mosaic:
            guard let pixelated = pixelatedImage else { break }
            let region = path.copy(
                strokingWithWidth: stroke.width, lineCap: .round, lineJoin: .round, miterLimit: 10
            )
            ctx.addPath(region)
            ctx.clip()
            ctx.interpolationQuality = .none
            drawBitmap(pixelated, in: bounds, ctx: ctx)
        case .text:
            // 白描边打底保证任何背景上可读,再用画笔色填充
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: stroke.fontSize, weight: .semibold),
                .foregroundColor: NSColor(cgColor: stroke.color) ?? .red,
                .strokeWidth: -4.0,
                .strokeColor: NSColor.white,
            ]
            ((stroke.text ?? "") as NSString).draw(at: stroke.points[0], withAttributes: attrs)
        case .rect:
            guard let r = shapeRect(for: stroke), r.width >= 1, r.height >= 1 else { break }
            ctx.setStrokeColor(stroke.color)
            ctx.setLineWidth(stroke.width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.stroke(r)
        case .ellipse:
            guard let r = shapeRect(for: stroke), r.width >= 1, r.height >= 1 else { break }
            ctx.setStrokeColor(stroke.color)
            ctx.setLineWidth(stroke.width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.strokeEllipse(in: r)
        }
        ctx.restoreGState()
    }

    private func drawIdleHint(at point: NSPoint) {
        let font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        let text = L10n.tr("拖动框选截图区域  ·  Enter / 确认 复制  ·  Esc / 右键 取消", "Drag to select  ·  Enter to copy  ·  Esc / Right-click to cancel")
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 12
        let boxW = size.width + pad * 2
        let boxH = size.height + pad
        var boxX = point.x - boxW / 2
        boxX = max(8, min(boxX, bounds.width - boxW - 8))
        let boxY = point.y - pad / 2
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: NSRect(x: boxX, y: boxY, width: boxW, height: boxH), xRadius: 9, yRadius: 9).fill()
        (text as NSString).draw(at: NSPoint(x: boxX + pad, y: boxY + pad / 2), withAttributes: attrs)
    }

    private func drawLabel(_ text: String, at point: NSPoint, centered: Bool = false) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 7
        let boxW = size.width + pad * 2
        let boxH = size.height + pad
        var boxX = point.x - pad
        if centered { boxX = point.x - boxW / 2 }
        boxX = max(4, min(boxX, bounds.width - boxW - 4))
        let boxY = max(4, point.y - pad / 2)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: NSRect(x: boxX, y: boxY, width: boxW, height: boxH), xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: NSPoint(x: boxX + pad, y: boxY + pad / 2), withAttributes: attrs)
    }

    /// 背景按块大小像素化(马赛克贴图),坐标与原图对齐
    private static func pixelated(image: CGImage, block: CGFloat) -> CGImage? {
        let block = max(2, block)
        let smallW = max(1, Int((CGFloat(image.width) / block).rounded()))
        let smallH = max(1, Int((CGFloat(image.height) / block).rounded()))
        let space = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard
            let small = CGContext(
                data: nil, width: smallW, height: smallH,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let big = CGContext(
                data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        small.interpolationQuality = .none
        small.draw(image, in: CGRect(x: 0, y: 0, width: smallW, height: smallH))
        guard let tiny = small.makeImage() else { return nil }
        big.interpolationQuality = .none
        big.draw(tiny, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return big.makeImage()
    }

    // MARK: 导出

    /// 把当前选区(含标注)按屏幕像素密度渲染为 PNG(无损,Retina 原生像素)
    func renderCropPNG() -> Data? {
        guard let sel = selectionRect else { return nil }
        let scale = CGFloat(bgImage.width) / bounds.width
        let pw = max(1, Int((sel.width * scale).rounded()))
        let ph = max(1, Int((sel.height * scale).rounded()))
        let colorSpace = bgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let cgCtx = CGContext(
            data: nil, width: pw, height: ph,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        cgCtx.interpolationQuality = .high
        cgCtx.setAllowsAntialiasing(true)
        cgCtx.setShouldAntialias(true)
        // 视图是翻转坐标(顶左原点);变换到像素空间
        cgCtx.translateBy(x: 0, y: CGFloat(ph))
        cgCtx.scaleBy(x: scale, y: -scale)
        cgCtx.translateBy(x: -sel.minX, y: -sel.minY)
        let nsCtx = NSGraphicsContext(cgContext: cgCtx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        drawScene(in: cgCtx, chrome: false)
        NSGraphicsContext.restoreGraphicsState()
        guard let cgOut = cgCtx.makeImage() else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgOut, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

// MARK: - 文字输入浮层

/// 截图选区内的单行文字输入框:Enter 确认、Esc 丢弃、点击框外确认
final class TextInputField: NSTextField {

    private let onComplete: (String, NSPoint) -> Void
    private let onCancel: () -> Void

    init(frame: NSRect, onComplete: @escaping (String, NSPoint) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frame)
        isEditable = true
        isSelectable = true
        target = self
        action = #selector(confirmAction)
    }

    required init?(coder: NSCoder) { fatalError("不支持从 NSCoder 初始化") }

    /// 点击浮层外时确认;返回 true 表示已确认(调用方应结束本次 mouseDown)
    func confirmIfNeeded(clickPoint: NSPoint) -> Bool {
        let local = convert(clickPoint, from: superview)
        guard !frame.contains(local) else { return false }
        complete()
        return true
    }

    private func complete() {
        let text = stringValue
        let origin = NSPoint(x: frame.minX, y: frame.midY)
        removeFromSuperview()
        onComplete(text, origin)
    }

    @objc private func confirmAction() {
        complete()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc 丢弃
            removeFromSuperview()
            onCancel()
            return
        }
        super.keyDown(with: event)
    }

    override func textDidEndEditing(_ notification: Notification) {
        // 失焦(如点击别处)由 confirmIfNeeded 处理,这里避免重复触发 action
    }
}
