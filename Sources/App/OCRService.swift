import AppKit
import Vision
import SharedCore

// MARK: - OCRService

/// 端侧文字识别:基于 Vision VNRecognizeTextRequest(离线、Neural Engine 加速)
/// 无需打包模型,零体积增量;支持中英,macOS 13+ 可用
enum OCRService {

    /// 识别 CGImage 中的文字,后台队列执行,主线程回调
    static func recognize(cgImage: CGImage, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let text = try recognizeSync(cgImage: cgImage)
                DispatchQueue.main.async { completion(.success(text)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// 同步识别(已在后台队列中)
    static func recognizeSync(cgImage: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // 优先中文(简/繁)+英文;系统会自动回退
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        if #available(macOS 13.0, *) {
            // revision 3 为 macOS 13+ 最准的版本
            request.revision = 3
        }
        // macOS 14+ 支持自动语言检测,可选
        if #available(macOS 14.0, *) {
            // 保持手动语言列表,自动检测会与列表取交集,更稳
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return "" }
        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        // 保留行分隔,便于复制后保持版式
        return lines.joined(separator: "\n")
    }
}

// MARK: - OCR 结果浮层

/// 识别完成后展示可复制文本的浮层:白底卡片+可滚动文本+复制/关闭
final class OCRResultWindow: NSPanel {

    private var onClose: (() -> Void)?

    static func show(text: String, at center: NSPoint) {
        let window = OCRResultWindow(text: text, center: center)
        window.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private init(text: String, center: NSPoint) {
        let width: CGFloat = 460
        let maxHeight: CGFloat = 420
        let minHeight: CGFloat = 160

        // 预估文本高度
        let font = UIStyle.Text.reading()
        let textWidth = width - 32
        let attr = [NSAttributedString.Key.font: font]
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: 2000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attr
        )
        let textHeight = ceil(bounding.height) + 16
        let contentHeight = min(max(textHeight + 56, minHeight), maxHeight)
        let panelHeight = contentHeight

        let rect = NSRect(x: center.x - width / 2, y: center.y - panelHeight / 2, width: width, height: panelHeight)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 3)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: panelHeight))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        container.layer?.cornerRadius = UIStyle.Metrics.radiusL
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 1
        container.layer?.borderColor = UIStyle.Palette.cardBorder.cgColor

        // 顶部提示
        let header = NSTextField(labelWithString: L10n.tr("已复制到剪贴板,可直接粘贴", "Copied to clipboard — paste anywhere"))
        header.font = UIStyle.Text.caption(.medium)
        header.textColor = UIStyle.Palette.textSecondary
        header.frame = NSRect(x: 16, y: panelHeight - 28, width: width - 32, height: 14)
        header.alignment = .left
        container.addSubview(header)

        // 文本滚动区
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 50, width: width - 24, height: panelHeight - 28 - 22 - 16))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.backgroundColor = UIStyle.Palette.inset.cgColor
        scroll.layer?.cornerRadius = UIStyle.Metrics.radiusM
        scroll.drawsBackground = false

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: textHeight))
        textView.string = text
        textView.font = font
        textView.textColor = UIStyle.Palette.text
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: textWidth, height: 2000)
        textView.textContainerInset = NSSize(width: 10, height: 8)

        scroll.documentView = textView
        container.addSubview(scroll)

        // 底部按钮:复制 / 关闭
        let btnCopy = NSButton(title: L10n.tr("复制", "Copy"), target: nil, action: nil)
        btnCopy.bezelStyle = .inline
        btnCopy.isBordered = false
        btnCopy.keyEquivalent = "\r"
        btnCopy.frame = NSRect(x: width - 160, y: 12, width: 72, height: 26)
        btnCopy.wantsLayer = true
        btnCopy.layer?.cornerRadius = UIStyle.Metrics.radiusM
        btnCopy.layer?.backgroundColor = UIStyle.Palette.accent.cgColor
        btnCopy.attributedTitle = NSAttributedString(string: L10n.tr("复制", "Copy"), attributes: [
            .font: UIStyle.Text.body(.medium),
            .foregroundColor: NSColor.white,
        ])
        container.addSubview(btnCopy)

        let btnClose = NSButton(title: L10n.tr("关闭", "Close"), target: nil, action: nil)
        btnClose.bezelStyle = .rounded
        btnClose.keyEquivalent = "\u{1b}"
        btnClose.frame = NSRect(x: width - 80, y: 12, width: 64, height: 26)
        btnClose.wantsLayer = true
        btnClose.layer?.cornerRadius = UIStyle.Metrics.radiusS
        container.addSubview(btnClose)

        contentView = container

        // 按钮行为
        btnCopy.target = self
        btnCopy.action = #selector(copyAction)
        btnClose.target = self
        btnClose.action = #selector(closeAction)

        // 关联 textView 供复制
        objc_setAssociatedObject(self, &AssociatedKeys.textView, textView, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &AssociatedKeys.text, text as NSString, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // 选中全部,方便二次复制
        DispatchQueue.main.async { textView.selectAll(nil) }
    }

    @objc private func copyAction() {
        if let t = objc_getAssociatedObject(self, &AssociatedKeys.text) as? String {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(t, forType: .string)
            ToastWindow.show(text: L10n.tr("已复制", "Copied"), at: NSPoint(x: frame.midX, y: frame.midY + 40))
        }
    }

    @objc private func closeAction() { close() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close(); return } // Esc
        super.keyDown(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private enum AssociatedKeys { static var textView: UInt8 = 0; static var text: UInt8 = 1 }
