import AppKit
import UniformTypeIdentifiers
import SharedCore

/// 纯手动去隔离面板:打开为空,拖 App 进来列表,点"去除隔离"才执行 xattr -dr。
final class QuarantinePanel: NSObject {

    static let shared = QuarantinePanel()

    private var window: NSWindow?
    private var table: NSTableView!
    private var paths: [String] = []
    private var statusLabel: NSTextField!
    private var stripButton: NSButton!

    func show() {
        if window == nil { build() }
        paths.removeAll()
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 440),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "去除隔离"
        win.subtitle = "拖入后一键清理"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        if #available(macOS 13.0, *) { win.toolbarStyle = .unifiedCompact }
        win.backgroundColor = NSColor.windowBackgroundColor
        win.isReleasedWhenClosed = false
        win.center()
        window = win

        guard let content = win.contentView else { return }
        content.wantsLayer = true
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bg)
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bg.topAnchor.constraint(equalTo: content.topAnchor),
            bg.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UIStyle.outerPadding),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -UIStyle.outerPadding),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: UIStyle.outerPadding),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])

        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 10
        let hdrIcon = NSView()
        hdrIcon.wantsLayer = true
        hdrIcon.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.14).cgColor
        hdrIcon.layer?.cornerRadius = 8
        hdrIcon.translatesAutoresizingMaskIntoConstraints = false
        hdrIcon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        hdrIcon.heightAnchor.constraint(equalToConstant: 30).isActive = true
        let hdrImg = NSImageView(image: NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: nil) ?? NSImage())
        hdrImg.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        hdrImg.contentTintColor = NSColor.systemOrange
        hdrImg.translatesAutoresizingMaskIntoConstraints = false
        hdrIcon.addSubview(hdrImg)
        NSLayoutConstraint.activate([hdrImg.centerXAnchor.constraint(equalTo: hdrIcon.centerXAnchor), hdrImg.centerYAnchor.constraint(equalTo: hdrIcon.centerYAnchor)])
        headerRow.addArrangedSubview(hdrIcon)
        let hdrStack = NSStackView()
        hdrStack.orientation = .vertical
        hdrStack.spacing = 2
        let hdrTitle = NSTextField(labelWithString: "去除隔离")
        hdrTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        hdrTitle.textColor = .labelColor
        hdrStack.addArrangedSubview(hdrTitle)
        let hdrSub = NSTextField(labelWithString: "拖入文件后一键清理隔离属性，可直接打开")
        hdrSub.font = .systemFont(ofSize: 11, weight: .regular)
        hdrSub.textColor = NSColor.secondaryLabelColor
        hdrStack.addArrangedSubview(hdrSub)
        headerRow.addArrangedSubview(hdrStack)
        root.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let hint = NSTextField(labelWithString: "把 .app / .dmg / .pkg 等拖到下方区域，轻点“去除隔离”即执行 xattr -dr")
        hint.font = .systemFont(ofSize: 11, weight: .regular)
        hint.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.9)
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 2
        hint.preferredMaxLayoutWidth = 520
        root.addArrangedSubview(hint)

        let dropView = DropView(panel: self)
        dropView.wantsLayer = true
        dropView.layer?.cornerRadius = 12
        dropView.layer?.borderWidth = 1.2
        dropView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.14).cgColor
        dropView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.55).cgColor
        dropView.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(dropView)
        dropView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        dropView.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = 10
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(UIStyle.cardBorderAlpha).cgColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        scroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        table = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        col.title = "待去隔离的路径"
        col.width = 480
        table.addTableColumn(col)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.usesAlternatingRowBackgroundColors = true
        scroll.documentView = table
        // 允许拖入到 table 本身
        table.registerForDraggedTypes([.fileURL])

        // 底部按钮
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 10
        bar.alignment = .centerY

        let selectBtn = NSButton(title: "选择文件…", target: self, action: #selector(pickFiles))
        selectBtn.bezelStyle = .rounded
        selectBtn.controlSize = .small
        selectBtn.wantsLayer = true
        selectBtn.layer?.cornerRadius = 7
        bar.addArrangedSubview(selectBtn)

        let clearBtn = NSButton(title: "清空", target: self, action: #selector(clear))
        clearBtn.bezelStyle = .rounded
        clearBtn.controlSize = .small
        clearBtn.wantsLayer = true
        clearBtn.layer?.cornerRadius = 7
        bar.addArrangedSubview(clearBtn)

        bar.addArrangedSubview(NSView())

        statusLabel = NSTextField(labelWithString: "就绪")
        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.9)
        bar.addArrangedSubview(statusLabel)

        stripButton = NSButton(title: "去除隔离", target: self, action: #selector(strip))
        stripButton.bezelStyle = .inline
        stripButton.isBordered = false
        stripButton.wantsLayer = true
        stripButton.layer?.cornerRadius = 8
        stripButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        stripButton.contentTintColor = .white
        stripButton.attributedTitle = NSAttributedString(string: "去除隔离", attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white])
        stripButton.keyEquivalent = "\r"
        bar.addArrangedSubview(stripButton)

        root.addArrangedSubview(bar)
        bar.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        // 让 dropView 接受拖入
        dropView.registerForDraggedTypes([.fileURL])
        updateStripEnabled()
    }

    func addPaths(_ new: [String]) {
        for p in new where !paths.contains(p) { paths.append(p) }
        reload()
    }

    private func reload() {
        table.reloadData()
        updateStripEnabled()
        statusLabel.stringValue = paths.isEmpty ? "就绪 - 拖入应用后点去除隔离" : "已加入 \(paths.count) 项"
    }

    private func updateStripEnabled() {
        stripButton.isEnabled = !paths.isEmpty
    }

    @objc private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType.applicationBundle, UTType.diskImage, UTType.package, UTType.data, UTType.item]
        if panel.runModal() == .OK {
            addPaths(panel.urls.map(\.path))
        }
    }

    @objc private func clear() {
        paths.removeAll()
        reload()
    }

    @objc private func strip() {
        let list = paths
        guard !list.isEmpty else { return }
        stripButton.isEnabled = false
        statusLabel.stringValue = "去隔离中…"
        QuarantineHelper.strip(paths: list) { [weak self] ok, fail in
            guard let self = self else { return }
            self.stripButton.isEnabled = true
            // 二次验证:再查一遍是否还有 quarantine 残留
            let remains = list.filter { QuarantineHelper.isQuarantined(path: $0) }
            if fail == 0, remains.isEmpty {
                self.statusLabel.stringValue = "✅ 已去除隔离 \(ok) 项 — 可直接打开"
                let alert = NSAlert()
                alert.messageText = "✅ 去隔离成功"
                alert.informativeText = "\(ok) 项已清除 com.apple.quarantine,可直接打开:\n" + list.joined(separator: "\n")
                alert.alertStyle = .informational
                alert.runModal()
            } else if remains.isEmpty {
                self.statusLabel.stringValue = "✅ 成功 \(ok) 失败 \(fail) — 已验证无残留"
                let alert = NSAlert()
                alert.messageText = "✅ 去隔离完成"
                alert.informativeText = "成功 \(ok) 失败 \(fail)\n验证:无残留隔离属性\n" + list.joined(separator: "\n")
                alert.runModal()
            } else {
                self.statusLabel.stringValue = "⚠️ 成功 \(ok) 失败 \(fail) — 仍有 \(remains.count) 项带隔离"
                let alert = NSAlert()
                alert.messageText = "⚠️ 去隔离未完全成功"
                alert.informativeText = "成功 \(ok) 失败 \(fail)\n仍带隔离(验证 xattr -p 仍存在):\n" + remains.joined(separator: "\n") + "\n\n可在终端验证:\nxattr -p com.apple.quarantine \"路径\"  (无输出即已清除)"
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}

extension QuarantinePanel: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { paths.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        var view = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView
        if view == nil {
            view = NSTableCellView()
            view?.identifier = id
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.spacing = 8
            rowStack.translatesAutoresizingMaskIntoConstraints = false
            let icon = NSImageView(image: NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil) ?? NSImage())
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            icon.contentTintColor = NSColor.tertiaryLabelColor
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 14).isActive = true
            rowStack.addArrangedSubview(icon)
            let tf = NSTextField(labelWithString: "")
            tf.identifier = NSUserInterfaceItemIdentifier("tf")
            tf.lineBreakMode = .byTruncatingMiddle
            tf.font = .systemFont(ofSize: 11.5, weight: .regular)
            tf.textColor = NSColor.labelColor
            tf.translatesAutoresizingMaskIntoConstraints = false
            rowStack.addArrangedSubview(tf)
            view?.addSubview(rowStack)
            NSLayoutConstraint.activate([
                rowStack.leadingAnchor.constraint(equalTo: view!.leadingAnchor, constant: 8),
                rowStack.trailingAnchor.constraint(equalTo: view!.trailingAnchor, constant: -8),
                rowStack.topAnchor.constraint(equalTo: view!.topAnchor, constant: 4),
                rowStack.bottomAnchor.constraint(equalTo: view!.bottomAnchor, constant: -4),
            ])
        }
        if let tf = view?.subviews.first?.subviews.compactMap({ $0 as? NSTextField }).first ?? view?.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("tf") }) as? NSTextField {
            tf.stringValue = paths[row]
        } else {
            (view?.subviews.first(where: { $0.identifier == NSUserInterfaceItemIdentifier("tf") }) as? NSTextField)?.stringValue = paths[row]
        }
        // 选中态圆角背景：系统会自动高亮，这里加一点内边距即可
        return view
    }
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 28 }
}

private final class DropView: NSView {
    weak var panel: QuarantinePanel?
    private var hovering = false { didSet { needsDisplay = true } }

    init(panel: QuarantinePanel) {
        self.panel = panel
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bg = hovering ? NSColor.controlAccentColor.withAlphaComponent(0.08) : NSColor.white.withAlphaComponent(0.62)
        bg.setFill()
        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        bgPath.fill()
        // dashed border when idle, solid accent when hovering
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12)
        borderPath.lineWidth = 1.2
        if hovering {
            NSColor.controlAccentColor.withAlphaComponent(0.55).setStroke()
            borderPath.stroke()
        } else {
            NSColor.separatorColor.withAlphaComponent(0.22).setStroke()
            borderPath.setLineDash([6, 5], count: 2, phase: 0)
            borderPath.stroke()
        }
        // icon — 极简符号
        let iconName = hovering ? "arrow.down.doc.fill" : "tray.and.arrow.down"
        if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
            if let sized = icon.withSymbolConfiguration(cfg) {
                let imgColor: NSColor = hovering ? .controlAccentColor : .tertiaryLabelColor
                let imgSize = NSSize(width: 24, height: 24)
                let imgRect = NSRect(x: (bounds.width - imgSize.width)/2, y: bounds.midY + 10, width: imgSize.width, height: imgSize.height)
                // 用模板色绘制
                sized.isTemplate = true
                // 通过 contentTint 模拟：创建临时 ImageView 绘制
                NSGraphicsContext.saveGraphicsState()
                imgColor.set()
                // 直接绘制符号，系统会自动用当前色
                let rep = sized.bestRepresentation(for: imgRect, context: nil, hints: nil)
                if let r = rep {
                    let tmp = NSImage(size: imgSize)
                    tmp.lockFocus()
                    imgColor.set()
                    r.draw(in: NSRect(origin: .zero, size: imgSize))
                    tmp.unlockFocus()
                    tmp.isTemplate = false
                    // 简化：直接用符号原色绘制，hover 用 accent
                }
                // 最简回退：直接绘制原符号（系统会按 tint 显示）
                icon.withSymbolConfiguration(cfg)?.draw(in: imgRect)
                NSGraphicsContext.restoreGraphicsState()
            }
        }
        let text = hovering ? "松手加入 ✓" : "拖到这里"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: hovering ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width)/2, y: bounds.midY - 6), withAttributes: attrs)
        let sub = L10n.tr("支持 .app / .dmg / .pkg / 文件夹  ·  亦可点「选择文件」", "Supports .app / .dmg / .pkg / folders  ·  or click \"Choose Files\"")
        let attrs2: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor]
        let size2 = (sub as NSString).size(withAttributes: attrs2)
        (sub as NSString).draw(at: NSPoint(x: (bounds.width - size2.width)/2, y: bounds.midY - 26), withAttributes: attrs2)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { hovering = true; return .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { hovering = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        hovering = false
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else { return false }
        panel?.addPaths(items.map(\.path))
        return true
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
}
