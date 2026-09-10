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
        UIStyle.applyWindowChrome(win, subtitle: "拖入后一键清理")
        win.center()
        window = win

        guard let content = win.contentView else { return }
        UIStyle.attachHUDMaterial(to: content)

        let root = UIStyle.vStack(spacing: UIStyle.Metrics.sp16)
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UIStyle.Metrics.windowPadding),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -UIStyle.Metrics.windowPadding),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: UIStyle.Metrics.windowPadding),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -UIStyle.Metrics.sp14),
        ])

        let headerRow = UIStyle.sectionHeader(
            title: "去除隔离",
            subtitle: "拖入文件后一键清理隔离属性，可直接打开",
            symbol: "shield.lefthalf.filled",
            tint: UIStyle.Palette.neutralTint
        )
        root.addArrangedSubview(headerRow)
        UIStyle.fillWidth(headerRow, in: root)

        let hint = UIStyle.hint("把 .app / .dmg / .pkg 等拖到下方区域，轻点“去除隔离”即执行 xattr -dr", maxWidth: 520, lines: 2)
        root.addArrangedSubview(hint)
        UIStyle.fillWidth(hint, in: root)

        let dropView = DropView(panel: self)
        dropView.wantsLayer = true
        dropView.layer?.cornerRadius = UIStyle.Metrics.radiusL
        dropView.layer?.masksToBounds = true
        dropView.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(dropView)
        dropView.heightAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
        UIStyle.fillWidth(dropView, in: root)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.wantsLayer = true
        scroll.layer?.cornerRadius = UIStyle.Metrics.radiusL
        scroll.layer?.borderWidth = 1
        scroll.layer?.borderColor = UIStyle.Palette.cardBorder.cgColor
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(scroll)
        scroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        UIStyle.fillWidth(scroll, in: root)

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
        let bar = UIStyle.hStack(spacing: UIStyle.Metrics.sp10)

        bar.addArrangedSubview(UIStyle.secondaryButton("选择文件…", target: self, action: #selector(pickFiles)))
        bar.addArrangedSubview(UIStyle.secondaryButton("清空", target: self, action: #selector(clear)))
        bar.addArrangedSubview(UIStyle.spacer())

        statusLabel = UIStyle.label("就绪", font: UIStyle.Text.caption(), color: UIStyle.Palette.textSecondary)
        bar.addArrangedSubview(statusLabel)

        stripButton = UIStyle.primaryButton("去除隔离", target: self, action: #selector(strip))
        stripButton.keyEquivalent = "\r"
        bar.addArrangedSubview(stripButton)

        root.addArrangedSubview(bar)
        UIStyle.fillWidth(bar, in: root)

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
            icon.contentTintColor = UIStyle.Palette.textTertiary
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 14).isActive = true
            rowStack.addArrangedSubview(icon)
            let tf = NSTextField(labelWithString: "")
            tf.identifier = NSUserInterfaceItemIdentifier("tf")
            tf.lineBreakMode = .byTruncatingMiddle
            tf.font = UIStyle.Text.body()
            tf.textColor = UIStyle.Palette.text
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
        let bg = hovering ? UIStyle.Palette.accentFaint : UIStyle.Palette.card
        bg.setFill()
        let bgPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: UIStyle.Metrics.radiusL, yRadius: UIStyle.Metrics.radiusL)
        bgPath.fill()
        // dashed border when idle, solid accent when hovering
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: UIStyle.Metrics.radiusL, yRadius: UIStyle.Metrics.radiusL)
        borderPath.lineWidth = 1.2
        if hovering {
            UIStyle.Palette.accent.withAlphaComponent(0.55).setStroke()
            borderPath.stroke()
        } else {
            UIStyle.Palette.controlBorder.setStroke()
            borderPath.setLineDash([6, 5], count: 2, phase: 0)
            borderPath.stroke()
        }
        // 图标：用 palette 着色配置，保证深浅色下都可见
        let iconName = hovering ? "arrow.down.doc.fill" : "tray.and.arrow.down"
        if let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            let imgColor: NSColor = hovering ? UIStyle.Palette.accent : UIStyle.Palette.textTertiary
            let cfg = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [imgColor]))
            if let sized = icon.withSymbolConfiguration(cfg) {
                let imgSize = NSSize(width: 24, height: 24)
                let imgRect = NSRect(x: (bounds.width - imgSize.width) / 2, y: bounds.midY + 10, width: imgSize.width, height: imgSize.height)
                sized.draw(in: imgRect)
            }
        }
        let text = hovering ? "松手加入 ✓" : "拖到这里"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIStyle.Text.reading(.medium),
            .foregroundColor: hovering ? UIStyle.Palette.accent : UIStyle.Palette.textSecondary,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: bounds.midY - 6), withAttributes: attrs)
        let sub = L10n.tr("支持 .app / .dmg / .pkg / 文件夹  ·  亦可点「选择文件」", "Supports .app / .dmg / .pkg / folders  ·  or click \"Choose Files\"")
        let attrs2: [NSAttributedString.Key: Any] = [.font: UIStyle.Text.caption(), .foregroundColor: UIStyle.Palette.textTertiary]
        let size2 = (sub as NSString).size(withAttributes: attrs2)
        (sub as NSString).draw(at: NSPoint(x: (bounds.width - size2.width) / 2, y: bounds.midY - 26), withAttributes: attrs2)
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
