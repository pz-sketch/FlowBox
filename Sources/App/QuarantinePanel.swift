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
    private var emptyLabel: NSTextField!

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
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 470),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.tr("去除隔离", "De-Quarantine")
        UIStyle.applyWindowChrome(win, subtitle: L10n.tr("拖入后一键清理", "Drop to clean"))
        win.center()
        window = win

        guard let content = win.contentView else { return }
        UIStyle.attachHUDMaterial(to: content)

        // 首行要避开标题栏上的红黄绿按钮，否则头部图标会和它们叠在一起
        let root = UIStyle.vStack(spacing: UIStyle.Metrics.sp14)
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UIStyle.Metrics.windowPadding),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -UIStyle.Metrics.windowPadding),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: UIStyle.Metrics.titlebarClearance),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -UIStyle.Metrics.sp16),
        ])

        let headerRow = UIStyle.sectionHeader(
            title: L10n.tr("去除隔离", "De-Quarantine"),
            subtitle: L10n.tr("拖入文件后一键清理隔离属性，可直接打开", "Drop files to strip the quarantine attribute and open them directly"),
            symbol: "shield.lefthalf.filled",
            tint: UIStyle.Palette.neutralTint
        )
        root.addArrangedSubview(headerRow)
        UIStyle.fillWidth(headerRow, in: root)

        let hint = UIStyle.hint(L10n.tr(
            "把 .app / .dmg / .pkg 等拖到下方区域，点「去除隔离」即执行 xattr -dr",
            "Drop .app / .dmg / .pkg below, then click De-Quarantine to run xattr -dr"))
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
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        table = NSTableView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        col.title = L10n.tr("待去隔离的路径", "Pending paths")
        col.width = 480
        table.addTableColumn(col)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.backgroundColor = .clear
        table.usesAlternatingRowBackgroundColors = false
        table.style = .plain
        scroll.documentView = table
        // 允许拖入到 table 本身
        table.registerForDraggedTypes([.fileURL])

        // 空列表时给一句占位说明，避免一片空白让人以为表格坏了
        // 占位文案挂在外层容器上：直接加到 NSScrollView 会被它自己的布局挪位
        let listWrapper = NSView()
        listWrapper.translatesAutoresizingMaskIntoConstraints = false
        listWrapper.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: listWrapper.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: listWrapper.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: listWrapper.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: listWrapper.bottomAnchor),
        ])

        emptyLabel = UIStyle.label(
            L10n.tr("列表为空 — 拖入文件或点「选择文件」", "Nothing here yet — drop files or click Choose Files"),
            font: UIStyle.Text.body(), color: UIStyle.Palette.textTertiary)
        listWrapper.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: listWrapper.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: listWrapper.centerYAnchor),
        ])

        let listCard = UIStyle.card(listWrapper, padding: 0)
        root.addArrangedSubview(listCard)
        UIStyle.fillWidth(listCard, in: root)
        listWrapper.heightAnchor.constraint(equalToConstant: 150).isActive = true

        // 底部按钮
        let bar = UIStyle.hStack(spacing: UIStyle.Metrics.sp10)

        bar.addArrangedSubview(UIStyle.secondaryButton(
            L10n.tr("选择文件…", "Choose Files…"), symbol: "folder",
            target: self, action: #selector(pickFiles)))
        bar.addArrangedSubview(UIStyle.secondaryButton(
            L10n.tr("清空", "Clear"), target: self, action: #selector(clear)))
        bar.addArrangedSubview(UIStyle.spacer())

        statusLabel = UIStyle.label("", font: UIStyle.Text.caption(), color: UIStyle.Palette.textSecondary)
        statusLabel.alignment = .right
        bar.addArrangedSubview(statusLabel)

        stripButton = UIStyle.primaryButton(
            L10n.tr("去除隔离", "De-Quarantine"), symbol: "checkmark.shield",
            target: self, action: #selector(strip))
        stripButton.keyEquivalent = "\r"
        bar.addArrangedSubview(stripButton)

        root.addArrangedSubview(bar)
        UIStyle.fillWidth(bar, in: root)

        updateStripEnabled()
    }

    func addPaths(_ new: [String]) {
        for p in new where !paths.contains(p) { paths.append(p) }
        reload()
    }

    private func reload() {
        table.reloadData()
        updateStripEnabled()
        emptyLabel.isHidden = !paths.isEmpty
        statusLabel.stringValue = paths.isEmpty
            ? L10n.tr("就绪 — 拖入文件后点「去除隔离」", "Ready — drop files, then De-Quarantine")
            : L10n.tr("已加入 \(paths.count) 项", "\(paths.count) item(s) added")
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
        statusLabel.stringValue = L10n.tr("去隔离中…", "De-quarantining…")
        QuarantineHelper.strip(paths: list) { [weak self] ok, fail in
            guard let self = self else { return }
            self.stripButton.isEnabled = true
            // 二次验证:再查一遍是否还有 quarantine 残留
            let remains = list.filter { QuarantineHelper.isQuarantined(path: $0) }
            if fail == 0, remains.isEmpty {
                self.statusLabel.stringValue = L10n.tr("已去除隔离 \(ok) 项 — 可直接打开", "De-quarantined \(ok) item(s) — ready to open")
                let alert = NSAlert()
                alert.messageText = L10n.tr("✅ 去隔离成功", "✅ De-quarantine Succeeded")
                alert.informativeText = L10n.tr(
                    "\(ok) 项已清除 com.apple.quarantine,可直接打开:",
                    "\(ok) item(s) cleared of com.apple.quarantine, ready to open:"
                ) + "\n" + list.joined(separator: "\n")
                alert.alertStyle = .informational
                alert.runModal()
            } else if remains.isEmpty {
                self.statusLabel.stringValue = L10n.tr("成功 \(ok) 失败 \(fail) — 已验证无残留", "Succeeded \(ok), failed \(fail) — verified, nothing left")
                let alert = NSAlert()
                alert.messageText = L10n.tr("✅ 去隔离完成", "✅ De-quarantine Finished")
                alert.informativeText = L10n.tr(
                    "成功 \(ok) 失败 \(fail)\n验证:无残留隔离属性",
                    "Succeeded \(ok), failed \(fail)\nVerified: no quarantine attributes left"
                ) + "\n" + list.joined(separator: "\n")
                alert.runModal()
            } else {
                self.statusLabel.stringValue = L10n.tr("成功 \(ok) 失败 \(fail) — 仍有 \(remains.count) 项带隔离", "Succeeded \(ok), failed \(fail) — \(remains.count) still quarantined")
                let alert = NSAlert()
                alert.messageText = L10n.tr("⚠️ 去隔离未完全成功", "⚠️ De-quarantine Incomplete")
                alert.informativeText = L10n.tr(
                    "成功 \(ok) 失败 \(fail)\n仍带隔离(验证 xattr -p 仍存在):",
                    "Succeeded \(ok), failed \(fail)\nStill quarantined (xattr -p still returns a value):"
                ) + "\n" + remains.joined(separator: "\n") + "\n\n" + L10n.tr(
                    "可在终端验证:\nxattr -p com.apple.quarantine \"路径\"  (无输出即已清除)",
                    "Verify in Terminal:\nxattr -p com.apple.quarantine \"path\"  (empty output means cleared)"
                )
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
        let text = hovering
            ? L10n.tr("松手加入", "Drop to add")
            : L10n.tr("拖到这里", "Drop here")
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
