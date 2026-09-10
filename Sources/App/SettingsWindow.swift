import AppKit
import AVFoundation
import SharedCore
import Carbon.HIToolbox
import os

/// 诊断日志:记录设置窗口的交互是否送达处理函数
func settingsDebugLog(_ message: String) {
    let url = URL(fileURLWithPath: "/tmp/flowbox-settings-debug.log")
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

/// 设置窗口:配置右键菜单显示项与新建文件模板,改动即时生效
/// 布局为分页式(Tab),避免单页过长
final class SettingsWindowController: NSObject, NSWindowDelegate {

    var window: NSWindow!
    var menuChecks: [String: NSButton] = [:]
    var listStack: NSStackView!
    var reverseCheck: NSButton!
    var smoothCheck: NSButton!
    var stepSlider: NSSlider!
    var stepField: NSTextField!
    var hiderCheck: NSButton!
    var shotRecorder: HotKeyRecorder!
    var shotHotKeyHint: NSTextField!
    var penWell: NSColorWell!
    var penSlider: NSSlider!
    var penValueLabel: NSTextField!
    var mosaicSlider: NSSlider!
    var mosaicValueLabel: NSTextField!
    var recRecorder: HotKeyRecorder!
    var recHotKeyHint: NSTextField!
    var recSystemAudioCheck: NSButton!
    var recMicCheck: NSButton!
    var recCameraCheck: NSButton!
    var recCameraCircleCheck: NSButton!
    var recCameraMirrorCheck: NSButton!
    var recCameraWidthSlider: NSSlider!
    var recCameraWidthLabel: NSTextField!

    // 人脸看守
    var presenceCheck: NSButton!
    var presenceStatusHint: NSTextField!
    var presenceLockStepper: NSStepper!
    var presenceLockValueLabel: NSTextField!
    var presenceConfirmStepper: NSStepper!
    var presenceConfirmValueLabel: NSTextField!
    var presenceGraceStepper: NSStepper!
    var presenceGraceValueLabel: NSTextField!
    var presenceSaveCheck: NSButton!
    var presenceStrangerCheck: NSButton!
    var presenceEnrollButton: NSButton!
    var presenceOwnerStatusLabel: NSTextField!

    /// 正在编辑的配置(每次打开窗口时从磁盘重读)
    var config = AppConfig.load()

    // 编辑面板(sheet)的控件与状态
    var sheet: NSWindow?
    var sheetNameField: NSTextField!
    var sheetFileField: NSTextField!
    var sheetTextView: NSTextView!
    var editingIndex = -1

    func show() {
        settingsDebugLog("打开设置窗口")
        if window == nil { buildWindow() }
        config = AppConfig.load()
        reloadMenuChecks()
        reloadTemplates()
        reloadScreenshotControls()
        reloadRecordingControls()
        reloadPresenceControls()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "settingsWindowFrame")
        // 关窗时若正在注册主人脸,取消并恢复看守,避免摄像头常开、控件锁死
        Task { @MainActor in PresenceMonitor.shared.cancelEnroll() }
    }

    // MARK: - 界面构建

    var segmented: NSSegmentedControl!
    var tabView: NSTabView!

    @objc private func segmentedChanged(_ sender: NSSegmentedControl) {
        tabView.selectTabViewItem(at: sender.selectedSegment)
    }

    private func buildWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: UIStyle.Metrics.windowWidth, height: UIStyle.Metrics.windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "FlowBox"
        UIStyle.applyWindowChrome(window, subtitle: L10n.tr("设置", "Settings"))
        window.minSize = NSSize(width: UIStyle.Metrics.minimumWindowWidth, height: UIStyle.Metrics.minimumWindowHeight)
        window.delegate = self
        if let savedFrame = UserDefaults.standard.string(forKey: "settingsWindowFrame") {
            window.setFrame(NSRectFromString(savedFrame), display: false)
        } else {
            window.center()
        }

        guard let content = window.contentView else { return }
        UIStyle.attachHUDMaterial(to: content)

        let root = UIStyle.vStack(spacing: UIStyle.Metrics.sp14)
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UIStyle.Metrics.windowPadding),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -UIStyle.Metrics.windowPadding),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: UIStyle.Metrics.windowTopInset),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -UIStyle.Metrics.sp12),
        ])

        let header = UIStyle.hStack(spacing: UIStyle.Metrics.sp10)
        let icon = NSImageView()
        if let appIcon = NSApp.applicationIconImage {
            icon.image = appIcon
        } else if let img = NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: nil) {
            icon.image = img
            icon.contentTintColor = UIStyle.Palette.accent
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        }
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: UIStyle.Metrics.chipSize).isActive = true
        icon.heightAnchor.constraint(equalToConstant: UIStyle.Metrics.chipSize).isActive = true
        icon.wantsLayer = true
        icon.layer?.cornerRadius = UIStyle.Metrics.radiusM
        icon.layer?.masksToBounds = true
        header.addArrangedSubview(icon)

        let titleStack = UIStyle.vStack(spacing: 1)
        titleStack.addArrangedSubview(UIStyle.label("FlowBox", font: UIStyle.Text.display(), color: UIStyle.Palette.text))
        titleStack.addArrangedSubview(UIStyle.label(
            L10n.tr("轻量 · 高效 · 不打扰  —  Finder 增强 / 截图 / 录屏 / 去隔离", "Lightweight · Efficient · Unobtrusive — Finder / Screenshot / Recording / Quarantine"),
            font: UIStyle.Text.micro(), color: UIStyle.Palette.textSecondary))
        header.addArrangedSubview(titleStack)
        header.addArrangedSubview(UIStyle.spacer())
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        header.addArrangedSubview(UIStyle.pill("v" + version, font: UIStyle.Text.mono(10), color: UIStyle.Palette.textTertiary))
        root.addArrangedSubview(header)
        UIStyle.fillWidth(header, in: root)

        let seg = NSSegmentedControl(labels: [L10n.tr("菜单", "Menu"), L10n.tr("鼠标", "Mouse"), L10n.tr("模板", "Templates"), L10n.tr("截图", "Screenshot"), L10n.tr("录屏", "Recording"), L10n.tr("人脸", "Presence"), L10n.tr("关于", "About")], trackingMode: .selectOne, target: self, action: #selector(segmentedChanged))
        seg.selectedSegment = 0
        seg.segmentStyle = .rounded
        seg.controlSize = .regular
        if #available(macOS 13.0, *) { seg.segmentDistribution = .fillEqually }
        // 为每段配 SF Symbol，让导航更直觉、更轻
        let symbols = ["list.bullet.indent", "computermouse", "doc.badge.plus", "camera.viewfinder", "video.badge.waveform", "person.crop.circle.badge.checkmark", "info.circle"]
        for (i, sym) in symbols.enumerated() {
            if let img = NSImage(systemSymbolName: sym, accessibilityDescription: nil) {
                seg.setImage(img, forSegment: i)
                seg.setImageScaling(.scaleProportionallyDown, forSegment: i)
            }
        }
        seg.translatesAutoresizingMaskIntoConstraints = false
        root.addArrangedSubview(seg)
        UIStyle.fillWidth(seg, in: root)
        segmented = seg

        tabView = NSTabView()
        tabView.tabViewType = .noTabsNoBorder
        tabView.tabViewBorderType = .none
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.wantsLayer = true
        root.addArrangedSubview(tabView)
        UIStyle.fillWidth(tabView, in: root)
        tabView.heightAnchor.constraint(greaterThanOrEqualToConstant: 408).isActive = true

        buildMenuTab(tabView: tabView)
        buildMouseTab(tabView: tabView)
        buildTemplateTab(tabView: tabView)
        buildScreenshotTab(tabView: tabView)
        buildRecordingTab(tabView: tabView)
        buildPresenceTab(tabView: tabView)
        buildAboutTab(tabView: tabView)
        applySettingsAccessibility(in: content)

        let footerSep = separatorView()
        root.addArrangedSubview(footerSep)
        UIStyle.fillWidth(footerSep, in: root)

        let footer = UIStyle.hStack(spacing: UIStyle.Metrics.sp6)
        footer.addArrangedSubview(UIStyle.statusDot(UIStyle.Palette.success.withAlphaComponent(0.9)))
        footer.addArrangedSubview(UIStyle.label(
            L10n.tr("改动即时生效 · 自动同步到配置文件", "Changes apply instantly · Auto-synced to config file"),
            font: UIStyle.Text.micro(), color: UIStyle.Palette.textSecondary))
        footer.addArrangedSubview(UIStyle.spacer())
        footer.addArrangedSubview(UIStyle.label(
            L10n.tr("⌘ ,  快速打开", "⌘ ,  to open quickly"),
            font: UIStyle.Text.footnote(), color: UIStyle.Palette.textTertiary))
        root.addArrangedSubview(footer)
        UIStyle.fillWidth(footer, in: root)
    }

    /// Reusable permission status card used by feature tabs.
    /// The button routes through PermissionManager so every page opens the same system pane.
    func permissionStatusCard(
        name: String,
        purpose: String,
        granted: Bool,
        settingsKey: String
    ) -> NSBox {
        let inner = UIStyle.vStack(spacing: UIStyle.Metrics.sp8)

        inner.addArrangedSubview(UIStyle.label(
            L10n.tr("权限", "Permissions") + " · " + name,
            font: UIStyle.Text.body(.semibold), color: UIStyle.Palette.text))

        inner.addArrangedSubview(UIStyle.hint(purpose, color: UIStyle.Palette.textSecondary, lines: 2))

        let row = UIStyle.hStack(spacing: UIStyle.Metrics.sp10)
        let pill = UIStyle.statusPill(
            granted ? L10n.tr("已授权", "Granted") : L10n.tr("需要授权", "Authorization required"),
            color: granted ? UIStyle.Palette.success : UIStyle.Palette.warning,
            background: granted ? UIStyle.Palette.successSoft : UIStyle.Palette.warningSoft)
        pill.setAccessibilityElement(true)
        pill.setAccessibilityLabel(L10n.tr("权限状态", "Permission status"))
        pill.setAccessibilityValue(granted ? L10n.tr("已授权", "Granted") : L10n.tr("需要授权", "Authorization required"))
        row.addArrangedSubview(pill)
        row.addArrangedSubview(UIStyle.spacer())

        let button = UIStyle.secondaryButton(L10n.tr("打开系统设置", "Open System Settings"), target: self, action: #selector(openPermissionSettings(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(settingsKey)
        button.setAccessibilityLabel(L10n.tr("打开系统设置中的" + name, "Open " + name + " in System Settings"))
        button.setAccessibilityHelp(purpose)
        row.addArrangedSubview(button)
        inner.addArrangedSubview(row)
        UIStyle.fillWidth(row, in: inner)
        return cardBox(containing: inner)
    }

    @objc func openPermissionSettings(_ sender: NSButton) {
        switch sender.identifier?.rawValue {
        case "accessibility": PermissionManager.openAccessibilitySettings()
        case "screenCapture": PermissionManager.openScreenCaptureSettings()
        case "camera":
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
        case "microphone":
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
        default: break
        }
    }

    /// Compact multi-permission card for recording-related media access.
    func permissionSummaryCard(_ items: [(name: String, granted: Bool, settingsKey: String)]) -> NSBox {
        let inner = UIStyle.vStack(spacing: UIStyle.Metrics.sp10)

        inner.addArrangedSubview(UIStyle.label(
            L10n.tr("录屏权限", "Recording permissions"),
            font: UIStyle.Text.body(.semibold), color: UIStyle.Palette.text))

        let statusRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        statusRow.distribution = .fillEqually
        for item in items {
            let pill = UIStyle.statusPill(
                (item.granted ? "✓ " : "! ") + item.name,
                color: item.granted ? UIStyle.Palette.success : UIStyle.Palette.warning,
                background: item.granted ? UIStyle.Palette.successSoft : UIStyle.Palette.warningSoft)
            pill.setAccessibilityElement(true)
            pill.setAccessibilityLabel(item.name)
            pill.setAccessibilityValue(item.granted
                ? L10n.tr("已授权", "Granted")
                : L10n.tr("需要授权", "Authorization required"))
            statusRow.addArrangedSubview(pill)
        }
        inner.addArrangedSubview(statusRow)
        UIStyle.fillWidth(statusRow, in: inner)

        let actionRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        for item in items {
            let button = UIStyle.secondaryButton(L10n.tr("设置", "Settings"), target: self, action: #selector(openPermissionSettings(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(item.settingsKey)
            button.setAccessibilityLabel(L10n.tr("打开" + item.name + "系统设置", "Open " + item.name + " settings"))
            button.setAccessibilityHelp(L10n.tr("在系统设置中管理此权限。", "Manage this permission in System Settings."))
            actionRow.addArrangedSubview(button)
        }
        inner.addArrangedSubview(actionRow)
        return cardBox(containing: inner)
    }

    func cardBox(containing inner: NSView) -> NSBox {
        UIStyle.card(inner)
    }

    /// Adds descriptive labels/help/value text without changing control behavior.
    func applySettingsAccessibility(in root: NSView) {
        segmented?.setAccessibilityLabel(L10n.tr("设置分类导航", "Settings category navigation"))
        segmented?.setAccessibilityHelp(L10n.tr("选择菜单、鼠标、模板、截图、录屏或关于。", "Choose Menu, Mouse, Templates, Screenshot, Recording, or About."))
        stepSlider?.setAccessibilityLabel(L10n.tr("最短滚动步长", "Minimum scroll step"))
        stepSlider?.setAccessibilityHelp(L10n.tr("调整每次滚动的最短距离。", "Adjust the minimum distance per scroll."))
        stepSlider?.setAccessibilityValue(String(format: "%.0f", stepSlider?.doubleValue ?? 0))
        penSlider?.setAccessibilityLabel(L10n.tr("画笔宽度", "Pen width"))
        penSlider?.setAccessibilityValue(String(format: "%.0f px", penSlider?.doubleValue ?? 0))
        mosaicSlider?.setAccessibilityLabel(L10n.tr("马赛克粒度", "Mosaic size"))
        mosaicSlider?.setAccessibilityValue(String(format: "%.0f px", mosaicSlider?.doubleValue ?? 0))
        recCameraWidthSlider?.setAccessibilityLabel(L10n.tr("画中画宽度", "Picture-in-picture width"))
        recCameraWidthSlider?.setAccessibilityValue(String(format: "%.0f px", recCameraWidthSlider?.doubleValue ?? 0))
        penWell?.setAccessibilityLabel(L10n.tr("画笔颜色", "Pen color"))
        shotRecorder?.setAccessibilityLabel(L10n.tr("截图快捷键录制器", "Screenshot hotkey recorder"))
        shotRecorder?.setAccessibilityHelp(L10n.tr("点击后按下新的组合键，按 Esc 取消。", "Click, then press a new shortcut; press Escape to cancel."))
        recRecorder?.setAccessibilityLabel(L10n.tr("录屏快捷键录制器", "Recording hotkey recorder"))
        recRecorder?.setAccessibilityHelp(L10n.tr("点击后按下新的组合键，按 Esc 取消。", "Click, then press a new shortcut; press Escape to cancel."))
    }

    func separatorView() -> NSView {
        UIStyle.hairline()
    }

    func sectionHeader(_ title: String, subtitle: String, symbol: String? = nil) -> NSView {
        UIStyle.sectionHeader(title: title, subtitle: subtitle, symbol: symbol)
    }

    /// 一行模板:[✓ 名称] [文件名] [↑] [↓] [编辑] [删除]
    func makeTemplateRow(index: Int, item: NewFileItem) -> NSView {
        let row = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        row.edgeInsets = NSEdgeInsets(top: UIStyle.Metrics.sp4, left: UIStyle.Metrics.sp6, bottom: UIStyle.Metrics.sp4, right: UIStyle.Metrics.sp6)

        let check = UIStyle.checkbox(item.displayName, target: self, action: #selector(toggleTemplate(_:)))
        check.tag = index
        check.state = item.enabled ? .on : .off
        row.addArrangedSubview(check)

        row.addArrangedSubview(UIStyle.pill(item.displayFilename))

        let up = smallButton(symbol: "chevron.up", action: #selector(moveTemplateUp(_:)), tag: index)
        let upLabel = L10n.tr("上移模板", "Move template up")
        up.setAccessibilityLabel(upLabel)
        up.toolTip = upLabel
        up.isEnabled = index > 0
        row.addArrangedSubview(up)

        let down = smallButton(symbol: "chevron.down", action: #selector(moveTemplateDown(_:)), tag: index)
        let downLabel = L10n.tr("下移模板", "Move template down")
        down.setAccessibilityLabel(downLabel)
        down.toolTip = downLabel
        down.isEnabled = index < config.newFiles.count - 1
        row.addArrangedSubview(down)

        let edit = smallButton(symbol: "square.and.pencil", action: #selector(editTemplate(_:)), tag: index)
        let editLabel = L10n.tr("编辑模板", "Edit template")
        edit.setAccessibilityLabel(editLabel)
        edit.toolTip = editLabel
        row.addArrangedSubview(edit)

        let remove = smallButton(symbol: "trash", action: #selector(removeTemplate(_:)), tag: index)
        let removeLabel = L10n.tr("删除模板", "Delete template")
        remove.setAccessibilityLabel(removeLabel)
        remove.toolTip = removeLabel
        row.addArrangedSubview(remove)

        return row
    }

    func smallButton(symbol: String, action: Selector, tag: Int) -> NSButton {
        let button = UIStyle.iconButton(symbol: symbol, target: self, action: action)
        button.tag = tag
        return button
    }

    // MARK: - 刷新

    func reloadMenuChecks() {
        let mirror = Mirror(reflecting: config.menu)
        for child in mirror.children {
            if let key = child.label, let check = menuChecks[key], let on = child.value as? Bool {
                check.state = on ? .on : .off
            }
        }
        // 有权限时按 isRunning,无权限时按配置值(避免每次打开都显示为关)
        let trust = PermissionManager.isAccessibilityTrusted && PermissionManager.canCreateEventTap()
        if trust {
            reverseCheck.state = ScrollReverser.shared.isRunning ? .on : .off
        } else {
            reverseCheck.state = config.scroll.reverseMouseWheel ? .on : .off
        }
        // 状态旁加提示(已授权/未授权)
        if let hint = reverseCheck.superview?.subviews.compactMap({ $0 as? NSTextField }).last {
            let s = PermissionManager.accessibilityStatusText()
            hint.stringValue = s.ok ? L10n.tr("触控板不受影响", "Trackpad unaffected") + " · \(s.text)" : L10n.tr("触控板不受影响;首次开启需要在系统设置里授权「辅助功能」", "Trackpad unaffected; grant Accessibility on first enable") + " · \(s.text)"
            hint.textColor = s.ok ? NSColor.systemGreen : NSColor.secondaryLabelColor
        }
        smoothCheck.state = config.scroll.smoothScrolling ? .on : .off
        hiderCheck.state = config.menuBar.hiderEnabled ? .on : .off
        // 屏幕录制状态
        if let hint = hiderCheck.superview?.subviews.compactMap({ $0 as? NSTextField }).last {
            let s = PermissionManager.screenCaptureStatusText()
            hint.stringValue = s.ok ? L10n.tr("已授权「屏幕录制」", "Screen Recording granted") + " · \(s.text)" : L10n.tr("开启后菜单栏最右多出箭头「«」:顶部图标被刘海/空间挤掉时,点箭头查看并打开它们;首次需授权「屏幕录制」", "Adds « at far right for notch overflow; requires Screen Recording") + " · \(s.text)"
            hint.textColor = s.ok ? NSColor.systemGreen : NSColor.secondaryLabelColor
        }
        updateSmoothControlsEnabled()
    }

    /// 流畅滚动关着时,步长控件置灰
    func updateSmoothControlsEnabled() {
        let on = smoothCheck.state == .on
        stepSlider.isEnabled = on
        stepField.isEnabled = on
    }

    func reloadTemplates() {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, item) in config.newFiles.enumerated() {
            let row = makeTemplateRow(index: index, item: item)
            row.translatesAutoresizingMaskIntoConstraints = false
            listStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: listStack.widthAnchor, constant: -16).isActive = true
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
            if index < config.newFiles.count - 1 {
                let sep = UIStyle.hairline()
                listStack.addArrangedSubview(sep)
                UIStyle.fillWidth(sep, in: listStack, inset: UIStyle.Metrics.sp8)
            }
        }
        if config.newFiles.isEmpty {
            listStack.addArrangedSubview(UIStyle.label(
                L10n.tr("暂无模板，点击「添加模板」新建", "No templates — click Add Template to create"),
                font: UIStyle.Text.body(), color: UIStyle.Palette.textSecondary))
        }
    }

    func save() {
        config.write()
    }

    // MARK: - 动作

    @objc func toggleMenu(_ sender: NSButton) {
        settingsDebugLog("toggleMenu key=\(sender.identifier?.rawValue ?? "?") state=\(sender.state.rawValue)")
        guard let key = sender.identifier?.rawValue else { return }
        let on = sender.state == .on
        switch key {
        case "copyFolder": config.menu.copyFolder = on
        case "copySelection": config.menu.copySelection = on
        case "openTerminal": config.menu.openTerminal = on
        case "newFile": config.menu.newFile = on
        default: return
        }
        save()
    }

    @objc func toggleTemplate(_ sender: NSButton) {
        settingsDebugLog("toggleTemplate index=\(sender.tag) state=\(sender.state.rawValue)")
        let index = sender.tag
        guard config.newFiles.indices.contains(index) else { return }
        config.newFiles[index].enabled = sender.state == .on
        save()
    }

    @objc func removeTemplate(_ sender: NSButton) {
        guard config.newFiles.indices.contains(sender.tag) else { return }
        config.newFiles.remove(at: sender.tag)
        save()
        reloadTemplates()
    }

    @objc func addTemplate() {
        config.newFiles.append(
            NewFileItem(name: L10n.tr("新模板", "New Template"), filename: L10n.tr("新建文件.txt", "New File.txt"), content: "", enabled: true)
        )
        save()
        reloadTemplates()
        openEditSheet(index: config.newFiles.count - 1)
    }

    @objc func resetTemplates() {
        // Restore only template data; preserve all other user settings.
        config.newFiles = AppConfig.defaultConfig().newFiles
        save()
        reloadTemplates()
    }

    @objc func toggleReverse(_ sender: NSButton) {
        settingsDebugLog("toggleReverse state=\(sender.state.rawValue)")
        if sender.state == .off {
            config.scroll.reverseMouseWheel = false
            save()
            applyScrollEngine()
            return
        }
        // 已有效授权 → 直接开,不弹窗
        if PermissionManager.isEffectivelyTrusted {
            config.scroll.reverseMouseWheel = true
            save()
            applyScrollEngine()
            if ScrollReverser.shared.isRunning { return }
            // 极少:检测 pass 但仍起不来 → 输入监控提示(单次)
            sender.state = .off
            config.scroll.reverseMouseWheel = false
            save()
            applyScrollEngine()
            guard shouldShowPermissionAlert(key: "accessibility_input") else { return }
            let alert = NSAlert()
            alert.messageText = L10n.tr("权限不足(输入监控)", "Permission Required (Input Monitoring)")
            alert.informativeText = L10n.tr("辅助功能已开,但创建事件拦截仍失败。请到 系统设置 → 隐私与安全性 → 输入监控 中也允许 FlowBox,然后重启。", "Accessibility granted but event tap still fails. Please also allow FlowBox in System Settings → Privacy & Security → Input Monitoring, then restart.")
            alert.addButton(withTitle: L10n.tr("打开系统设置", "Open System Settings"))
            alert.addButton(withTitle: L10n.tr("取消", "Cancel"))
            if alert.runModal() == .alertFirstButtonReturn {
                PermissionManager.openInputMonitoringSettings()
            }
            return
        }
        // 未授权:先弹系统授权框(最多弹这一次)
        let prompted = PermissionManager.requestAccessibilityPrompt()
        // 给系统 0.8s 写入 TCC,轮询一次
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak sender] in
            guard let self = self, let sender = sender else { return }
            // 后台轮询最多 3 秒等 tccd 落盘
            DispatchQueue.global(qos: .userInitiated).async {
                let ok = PermissionManager.waitForTrust(timeout: 3.0)
                DispatchQueue.main.async {
                    if ok {
                        self.config.scroll.reverseMouseWheel = true
                        self.save()
                        self.applyScrollEngine()
                        if ScrollReverser.shared.isRunning {
                            sender.state = .on
                            self.reloadMenuChecks()
                            return
                        }
                    }
                    // 仍失败 → 单次引导弹窗(用户取消授权或未重启)
                    sender.state = .off
                    self.config.scroll.reverseMouseWheel = false
                    self.save()
                    self.applyScrollEngine()
                    self.reloadMenuChecks()
                    guard self.shouldShowPermissionAlert(key: "accessibility") else { return }
                    let alert = NSAlert()
                    alert.messageText = L10n.tr("需要「辅助功能」权限", "Accessibility Permission Required")
                    alert.informativeText = """
                    请到 系统设置 → 隐私与安全性 → 辅助功能 中允许「FlowBox」
                    (若刚点过允许,请把开关关掉再打开,必要时重启 FlowBox),
                    然后回来重新打开此开关;若仍无效,到 输入监控 里同样操作一次。
                    """
                    alert.addButton(withTitle: L10n.tr("打开系统设置", "Open System Settings"))
                    alert.addButton(withTitle: L10n.tr("取消", "Cancel"))
                    if alert.runModal() == .alertFirstButtonReturn {
                        PermissionManager.openAccessibilitySettings()
                    }
                }
            }
        }
        // 乐观:先按开启保存,等回调再校正,避免 UI 闪烁
        config.scroll.reverseMouseWheel = true
        save()
        applyScrollEngine()
        _ = prompted
    }

    private var lastPermissionAlert: [String: Date] = [:]
    func shouldShowPermissionAlert(key: String) -> Bool {
        if let last = lastPermissionAlert[key], Date().timeIntervalSince(last) < 5 { return false }
        lastPermissionAlert[key] = Date()
        return true
    }

    @objc func moveTemplateUp(_ sender: NSButton) {
        let index = sender.tag
        guard index > 0, config.newFiles.indices.contains(index) else { return }
        config.newFiles.swapAt(index, index - 1)
        save()
        reloadTemplates()
    }

    @objc func moveTemplateDown(_ sender: NSButton) {
        let index = sender.tag
        guard config.newFiles.indices.contains(index), index < config.newFiles.count - 1 else { return }
        config.newFiles.swapAt(index, index + 1)
        save()
        reloadTemplates()
    }

    // MARK: - 平滑滚动

    /// 按最新配置决定引擎启停,并同步运行参数(反转或平滑任一开启都需要引擎)
    func applyScrollEngine() {
        let running = ScrollReverser.shared.isRunning
        let needed = config.scroll.reverseMouseWheel || config.scroll.smoothScrolling
        if needed && !running { _ = ScrollReverser.shared.start() }
        if !needed && running { ScrollReverser.shared.stop() }
        ScrollReverser.shared.reverseEnabled = config.scroll.reverseMouseWheel
        ScrollReverser.shared.smoothEnabled = config.scroll.smoothScrolling
        ScrollReverser.shared.minStep = config.scroll.minStep
        reverseCheck.state = ScrollReverser.shared.isRunning && config.scroll.reverseMouseWheel ? .on : .off
    }

    @objc func toggleSmooth(_ sender: NSButton) {
        settingsDebugLog("toggleSmooth state=\(sender.state.rawValue)")
        let on = sender.state == .on
        if on, !PermissionManager.isEffectivelyTrusted {
            // 与反转同一套授权流程,避免重复弹
            _ = PermissionManager.requestAccessibilityPrompt()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                DispatchQueue.global(qos: .userInitiated).async {
                    let ok = PermissionManager.waitForTrust(timeout: 3.0)
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if ok {
                            self.config.scroll.smoothScrolling = true
                            self.save()
                            self.applyScrollEngine()
                            self.updateSmoothControlsEnabled()
                            self.reloadMenuChecks()
                            return
                        }
                        sender.state = .off
                        self.config.scroll.smoothScrolling = false
                        self.save()
                        self.applyScrollEngine()
                        self.updateSmoothControlsEnabled()
                    }
                }
            }
            config.scroll.smoothScrolling = true
            save()
            applyScrollEngine()
            updateSmoothControlsEnabled()
            return
        }
        config.scroll.smoothScrolling = on
        updateSmoothControlsEnabled()
        save()
        applyScrollEngine()
    }

    // MARK: - 菜单栏收纳

    @objc func toggleHider(_ sender: NSButton) {
        let on = sender.state == .on
        settingsDebugLog("toggleHider state=\(sender.state.rawValue)")
        config.menuBar.hiderEnabled = on
        save()
        MenuBarHider.shared.setEnabled(on)
    }



    @objc func stepSliderChanged(_ sender: NSSlider) {
        stepField.stringValue = String(format: "%.0f", sender.doubleValue)
        syncStepConfig(sender.doubleValue)
    }

    @objc func stepFieldChanged() {
        let clamped = min(max(stepField.doubleValue, 5), 300)
        if abs(clamped - stepField.doubleValue) > 0.001 {
            stepField.stringValue = String(format: "%.0f", clamped)
        }
        stepSlider.doubleValue = clamped
        syncStepConfig(clamped)
    }

    @objc func stepStepperChanged(_ sender: NSStepper) {
        stepSlider.doubleValue = sender.doubleValue
        stepField.stringValue = String(format: "%.0f", sender.doubleValue)
        syncStepConfig(sender.doubleValue)
    }

    func syncStepConfig(_ value: Double) {
        settingsDebugLog("minStep=\(value)")
        config.scroll.minStep = value
        save()
        ScrollReverser.shared.minStep = value
    }

    @objc func editTemplate(_ sender: NSButton) {
        openEditSheet(index: sender.tag)
    }

    func openEditSheet(index: Int) {
        guard config.newFiles.indices.contains(index) else { return }
        editingIndex = index
        let item = config.newFiles[index]

        let sheetWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.title = L10n.tr("编辑模板", "Edit Template")

        let content = NSView(frame: sheetWindow.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        sheetWindow.contentView = content

        let stack = UIStyle.vStack(spacing: UIStyle.Metrics.sp8)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: UIStyle.Metrics.sp16),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -UIStyle.Metrics.sp16),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: UIStyle.Metrics.sp14),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -UIStyle.Metrics.sp12),
        ])

        let nameLabel = UIStyle.label(L10n.tr("名称(菜单里显示)", "Name (shown in menu)"),
                                      font: UIStyle.Text.caption(), color: UIStyle.Palette.textSecondary)
        sheetNameField = NSTextField()
        sheetNameField.stringValue = item.name
        sheetNameField.placeholderString = L10n.tr("如:Markdown 文档", "e.g. Markdown")
        stack.addArrangedSubview(nameLabel)
        stack.addArrangedSubview(sheetNameField)
        sheetNameField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let fileLabel = UIStyle.label(L10n.tr("文件名(重名自动加序号)", "File name (auto-numbered on collision)"),
                                      font: UIStyle.Text.caption(), color: UIStyle.Palette.textSecondary)
        sheetFileField = NSTextField()
        sheetFileField.stringValue = item.filename
        sheetFileField.placeholderString = L10n.tr("如:新建文档.md", "e.g. Document.md")
        stack.addArrangedSubview(fileLabel)
        stack.addArrangedSubview(sheetFileField)
        sheetFileField.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let contentLabel = NSTextField(
            labelWithString: item.isBase64
                ? L10n.tr("模板内容(二进制 Base64,一般无需修改)", "Template content (binary Base64, usually leave as-is)")
                : L10n.tr("模板内容(文件初始内容)", "Template content (initial file content)")
        )
        contentLabel.font = UIStyle.Text.caption()
        contentLabel.textColor = UIStyle.Palette.textSecondary
        contentLabel.lineBreakMode = .byWordWrapping
        contentLabel.maximumNumberOfLines = 2
        stack.addArrangedSubview(contentLabel)

        let textScroll = NSScrollView()
        textScroll.hasVerticalScroller = true
        textScroll.borderType = .noBorder
        textScroll.drawsBackground = true
        textScroll.backgroundColor = .textBackgroundColor
        textScroll.wantsLayer = true
        textScroll.layer?.cornerRadius = UIStyle.Metrics.radiusM
        textScroll.layer?.borderWidth = 1
        textScroll.layer?.borderColor = UIStyle.Palette.controlBorder.cgColor
        textScroll.layer?.masksToBounds = true
        textScroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            textScroll.heightAnchor.constraint(equalToConstant: 150),
        ])
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 150))
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.font = UIStyle.Text.mono(12)
        textView.textContainerInset = NSSize(width: UIStyle.Metrics.sp6, height: UIStyle.Metrics.sp6)
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = item.content
        textView.autoresizingMask = [.width]
        textScroll.documentView = textView
        sheetTextView = textView
        stack.addArrangedSubview(textScroll)

        let buttons = UIStyle.hStack(spacing: UIStyle.Metrics.sp10)
        let cancel = UIStyle.secondaryButton(L10n.tr("取消", "Cancel"), target: self, action: #selector(sheetCancel))
        cancel.keyEquivalent = "\u{1b}"
        let ok = UIStyle.primaryButton(L10n.tr("保存", "Save"), target: self, action: #selector(sheetSave))
        ok.keyEquivalent = "\r"
        buttons.addArrangedSubview(cancel)
        buttons.addArrangedSubview(ok)
        stack.addArrangedSubview(buttons)

        sheet = sheetWindow
        window.beginSheet(sheetWindow)
    }

    @objc func sheetCancel() {
        guard let sheetWindow = sheet else { return }
        window.endSheet(sheetWindow)
        sheet = nil
    }

    @objc func sheetSave() {
        guard let sheetWindow = sheet, config.newFiles.indices.contains(editingIndex) else { return }
        let name = sheetNameField.stringValue.trimmingCharacters(in: .whitespaces)
        let filename = sheetFileField.stringValue.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { config.newFiles[editingIndex].name = name }
        if !filename.isEmpty { config.newFiles[editingIndex].filename = filename }
        config.newFiles[editingIndex].content = sheetTextView.string
        save()
        window.endSheet(sheetWindow)
        sheet = nil
        reloadTemplates()
    }

    // MARK: - 截图/录屏

    func reloadRecordingControls() {
        let rc = config.recording
        let combo = HotKeyCenter.comboName(keyCode: UInt32(rc.hotKeyCode), modifiers: UInt32(rc.hotKeyModifiers))
        recRecorder.stringValue = combo
        recRecorder.savedName = combo
        recHotKeyHint.stringValue = ""
        recSystemAudioCheck.state = rc.captureSystemAudio ? .on : .off
        recMicCheck.state = rc.captureMicrophone ? .on : .off
        recCameraCheck.state = rc.captureCamera ? .on : .off
        recCameraCircleCheck.state = rc.cameraIsCircle ? .on : .off
        recCameraMirrorCheck.state = rc.cameraMirrored ? .on : .off
        recCameraWidthSlider.doubleValue = rc.cameraWidth
        recCameraWidthLabel.stringValue = "\(Int(rc.cameraWidth))"
        updateCameraControlsEnabled()
    }

    func updateCameraControlsEnabled() {
        let on = recCameraCheck.state == .on
        recCameraWidthSlider.isEnabled = on
        recCameraCircleCheck.isEnabled = on
        recCameraMirrorCheck.isEnabled = on
    }

    func reloadScreenshotControls() {
        let sc = config.screenshot
        let combo = HotKeyCenter.comboName(keyCode: UInt32(sc.hotKeyCode), modifiers: UInt32(sc.hotKeyModifiers))
        shotRecorder.stringValue = combo
        shotRecorder.savedName = combo
        shotHotKeyHint.stringValue = ""
        penWell.color = NSColor(hexString: sc.penColorHex) ?? .systemRed
        penSlider.doubleValue = sc.penWidth
        penValueLabel.stringValue = "\(Int(sc.penWidth)) px"
        mosaicSlider.doubleValue = sc.mosaicBlock
        mosaicValueLabel.stringValue = "\(Int(sc.mosaicBlock)) px"
    }

    func applyHotKey(code: UInt32, mods: UInt32) {
        settingsDebugLog("截图快捷键=\(HotKeyCenter.comboName(keyCode: code, modifiers: mods))")
        config.screenshot.hotKeyCode = Int(code)
        config.screenshot.hotKeyModifiers = Int(mods)
        save()
        let ok = HotKeyCenter.shared.register(keyCode: code, modifiers: mods, kind: .screenshot)
        shotHotKeyHint.stringValue = ok ? "" : L10n.tr("注册失败,可能被其它应用占用", "Registration failed — may be in use")
    }

    func applyRecHotKey(code: UInt32, mods: UInt32) {
        settingsDebugLog("录屏快捷键=\(HotKeyCenter.comboName(keyCode: code, modifiers: mods))")
        config.recording.hotKeyCode = Int(code)
        config.recording.hotKeyModifiers = Int(mods)
        save()
        let ok = HotKeyCenter.shared.register(keyCode: code, modifiers: mods, kind: .recording)
        recHotKeyHint.stringValue = ok ? "" : L10n.tr("注册失败,可能被其它应用占用", "Registration failed — may be in use")
    }

    @objc func toggleRecSystemAudio(_ sender: NSButton) {
        config.recording.captureSystemAudio = sender.state == .on
        save()
    }
    @objc func toggleRecMic(_ sender: NSButton) {
        config.recording.captureMicrophone = sender.state == .on
        save()
    }
    @objc func toggleRecCamera(_ sender: NSButton) {
        let on = sender.state == .on
        if on {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.config.recording.captureCamera = true
                            self.save()
                            self.updateCameraControlsEnabled()
                        } else {
                            sender.state = .off
                            self.config.recording.captureCamera = false
                            self.save()
                            self.updateCameraControlsEnabled()
                        }
                    }
                }
                config.recording.captureCamera = true
                save()
                updateCameraControlsEnabled()
                return
            case .denied, .restricted:
                sender.state = .off
                let alert = NSAlert()
                alert.messageText = L10n.tr("需要「摄像头」权限", "Camera Permission Required")
                alert.informativeText = L10n.tr("请到 系统设置 → 隐私与安全性 → 摄像头 中允许「FlowBox」。", "Please allow FlowBox in System Settings → Privacy & Security → Camera.")
                alert.addButton(withTitle: L10n.tr("打开系统设置", "Open System Settings"))
                alert.addButton(withTitle: L10n.tr("取消", "Cancel"))
                if alert.runModal() == .alertFirstButtonReturn,
                   let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                    NSWorkspace.shared.open(url)
                }
                return
            default: break
            }
        }
        config.recording.captureCamera = on
        save()
        updateCameraControlsEnabled()
    }
    @objc func toggleCameraCircle(_ sender: NSButton) {
        config.recording.cameraIsCircle = sender.state == .on
        save()
    }
    @objc func toggleCameraMirror(_ sender: NSButton) {
        config.recording.cameraMirrored = sender.state == .on
        save()
    }
    @objc func cameraWidthChanged(_ sender: NSSlider) {
        recCameraWidthLabel.stringValue = "\(Int(sender.doubleValue))"
        config.recording.cameraWidth = sender.doubleValue
        save()
    }

    @objc func penColorChanged(_ sender: NSColorWell) {
        settingsDebugLog("画笔颜色=\(sender.color.hexString)")
        config.screenshot.penColorHex = sender.color.hexString
        save()
    }

    @objc func penWidthChanged(_ sender: NSSlider) {
        penValueLabel.stringValue = "\(Int(sender.doubleValue)) px"
        config.screenshot.penWidth = sender.doubleValue
        save()
    }

    @objc func mosaicChanged(_ sender: NSSlider) {
        mosaicValueLabel.stringValue = "\(Int(sender.doubleValue)) px"
        config.screenshot.mosaicBlock = sender.doubleValue
        save()
    }
}
