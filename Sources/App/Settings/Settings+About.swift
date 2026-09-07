import AppKit
import SharedCore
import os

extension SettingsWindowController {
    func buildAboutTab(tabView: NSTabView) {
        let aboutTab = NSTabViewItem(identifier: "about")
        aboutTab.label = L10n.tr("关于", "About")
        let aboutView = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        aboutView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: aboutView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: aboutView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: aboutView.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: aboutView.bottomAnchor, constant: -8),
        ])

        // Title with large icon
        let hero = NSStackView()
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.spacing = 14

        let iconBox = NSView()
        iconBox.wantsLayer = true
        iconBox.layer?.cornerRadius = 12
        iconBox.layer?.masksToBounds = true
        iconBox.layer?.shadowColor = NSColor.black.cgColor
        iconBox.layer?.shadowOpacity = 0.08
        iconBox.layer?.shadowRadius = 12
        iconBox.layer?.shadowOffset = NSSize(width: 0, height: 4)
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        iconBox.widthAnchor.constraint(equalToConstant: 56).isActive = true
        iconBox.heightAnchor.constraint(equalToConstant: 56).isActive = true

        let iconView = NSImageView()
        if let appIcon = NSApp.applicationIconImage {
            iconView.image = appIcon
        } else if let img = NSImage(systemSymbolName: "sparkles.rectangle.stack.fill", accessibilityDescription: nil) {
            iconView.image = img
            iconView.contentTintColor = NSColor.controlAccentColor
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: iconBox.leadingAnchor, constant: 6),
            iconView.trailingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: -6),
            iconView.topAnchor.constraint(equalTo: iconBox.topAnchor, constant: 6),
            iconView.bottomAnchor.constraint(equalTo: iconBox.bottomAnchor, constant: -6),
        ])
        hero.addArrangedSubview(iconBox)

        let titleStack = NSStackView()
        titleStack.orientation = .vertical
        titleStack.spacing = 3
        let nameLabel = NSTextField(labelWithString: "FlowBox")
        nameLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        nameLabel.textColor = .labelColor
        titleStack.addArrangedSubview(nameLabel)
        let subLabel = NSTextField(labelWithString: L10n.tr("极简工具箱 — 轻量 · 高效 · 不打扰", "FlowBox — Lightweight · Efficient · Unobtrusive"))
        subLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subLabel.textColor = NSColor.secondaryLabelColor
        titleStack.addArrangedSubview(subLabel)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let versionLabel = NSTextField(labelWithString: L10n.tr("版本", "Version") + " \(version)  ·  net.ai2048.flowbox")
        versionLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        versionLabel.textColor = NSColor.tertiaryLabelColor
        titleStack.addArrangedSubview(versionLabel)
        hero.addArrangedSubview(titleStack)
        stack.addArrangedSubview(hero)
        hero.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Language — prominent top card
        stack.addArrangedSubview(sectionHeader(L10n.tr("界面语言", "Language"), subtitle: L10n.tr("切换后重启生效", "Restart to apply after switching"), symbol: "globe"))
        let langInner = NSStackView()
        langInner.orientation = .horizontal
        langInner.spacing = 12
        langInner.alignment = .centerY
        let langIcon = NSImageView(image: NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage())
        langIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        langIcon.contentTintColor = .controlAccentColor
        langInner.addArrangedSubview(langIcon)
        let langLabel2 = NSTextField(labelWithString: L10n.tr("界面语言", "Language"))
        langLabel2.font = .systemFont(ofSize: 13, weight: .semibold)
        langInner.addArrangedSubview(langLabel2)
        let langPop2 = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
        langPop2.addItems(withTitles: [L10n.tr("跟随系统", "Follow System"), "中文", "English"])
        let cur2 = AppConfig.load().language
        if cur2 == "en" { langPop2.selectItem(at: 2) } else if cur2 == "zh" { langPop2.selectItem(at: 1) } else { langPop2.selectItem(at: 0) }
        langPop2.target = self
        langPop2.action = #selector(languageChanged(_:))
        langPop2.controlSize = .regular
        langPop2.font = .systemFont(ofSize: 13)
        langInner.addArrangedSubview(langPop2)
        let langHint2 = NSTextField(labelWithString: L10n.tr("重启后生效", "Restart to apply"))
        langHint2.font = .systemFont(ofSize: 11)
        langHint2.textColor = .secondaryLabelColor
        langInner.addArrangedSubview(langHint2)
        let langCard = cardBox(containing: langInner)
        stack.addArrangedSubview(langCard)
        langCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Features card
        stack.addArrangedSubview(sectionHeader(L10n.tr("功能一览", "Features"), subtitle: L10n.tr("为 Finder 与创作流程做小而美的增强", "Small, beautiful enhancements for Finder & creation"), symbol: "star.circle"))
        let featInner = NSStackView()
        featInner.orientation = .vertical
        featInner.spacing = 8
        featInner.alignment = .leading
        let features: [(String, String)] = [
            ("list.bullet.indent", L10n.tr("右键增强 — 复制路径 / 终端打开 / 新建文件模板", "Finder tweak — Copy path / Open in Terminal / New file from template")),
            ("computermouse", L10n.tr("鼠标增强 — 外接鼠标滚轮反向 / 平滑惯性滚动", "Mouse — Reverse wheel / Smooth inertial scrolling")),
            ("camera.viewfinder", L10n.tr("框选截图 — 画笔 / 马赛克 / 文字 / 形状 / 复制保存", "Screenshot — Pen / Mosaic / Text / Shapes / Copy & Save")),
            ("video.badge.waveform", L10n.tr("全屏录屏 — 系统声音 / 麦克风 / 摄像头画中画", "Recording — System audio / Mic / Camera PiP")),
            ("shield.lefthalf.filled", L10n.tr("去隔离 — 拖入 .app/.dmg/.pkg 一键清理 quarantine", "De-Quarantine — Drop .app/.dmg/.pkg to strip quarantine")),
            ("menubar.rectangle", L10n.tr("菜单栏收纳 — 刘海/空间不足时收纳右侧图标", "Menu Bar — Collapse overflow icons behind notch")),
        ]
        for (sym, text) in features {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .centerY
            let iv = NSImageView(image: NSImage(systemSymbolName: sym, accessibilityDescription: nil) ?? NSImage())
            iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            iv.contentTintColor = NSColor.controlAccentColor
            row.addArrangedSubview(iv)
            let lb = NSTextField(labelWithString: text)
            lb.font = .systemFont(ofSize: 11, weight: .regular)
            lb.textColor = NSColor.labelColor
            lb.lineBreakMode = .byWordWrapping
            row.addArrangedSubview(lb)
            featInner.addArrangedSubview(row)
        }
        let featCard = cardBox(containing: featInner)
        stack.addArrangedSubview(featCard)
        featCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Links & actions
        stack.addArrangedSubview(sectionHeader(L10n.tr("链接与支持", "Links & Support"), subtitle: L10n.tr("配置、反馈与开源", "Config, feedback & open source"), symbol: "link.circle"))
        let linkInner = NSStackView()
        linkInner.orientation = .vertical
        linkInner.spacing = 10

        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 8

        let configBtn = NSButton(title: L10n.tr("打开配置文件夹", "Open Config Folder"), target: self, action: #selector(openConfigFolder))
        configBtn.bezelStyle = .rounded
        configBtn.controlSize = .small
        configBtn.wantsLayer = true
        configBtn.layer?.cornerRadius = 7
        if let img = NSImage(systemSymbolName: "folder", accessibilityDescription: nil) { configBtn.image = img; configBtn.imagePosition = .imageLeading }
        btnRow.addArrangedSubview(configBtn)

        let logBtn = NSButton(title: L10n.tr("打开日志", "Open Logs"), target: self, action: #selector(openLogFolder))
        logBtn.bezelStyle = .rounded
        logBtn.controlSize = .small
        logBtn.wantsLayer = true
        logBtn.layer?.cornerRadius = 7
        if let img = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) { logBtn.image = img; logBtn.imagePosition = .imageLeading }
        btnRow.addArrangedSubview(logBtn)

        let copyInfoBtn = NSButton(title: L10n.tr("复制版本信息", "Copy Version"), target: self, action: #selector(copyVersionInfo))
        copyInfoBtn.bezelStyle = .rounded
        copyInfoBtn.controlSize = .small
        copyInfoBtn.wantsLayer = true
        copyInfoBtn.layer?.cornerRadius = 7
        if let img = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) { copyInfoBtn.image = img; copyInfoBtn.imagePosition = .imageLeading }
        btnRow.addArrangedSubview(copyInfoBtn)

        linkInner.addArrangedSubview(btnRow)

        let hint = NSTextField(labelWithString: L10n.tr("配置文件位于 ~/.config/flowbox/  ·  日志在 /tmp/flowbox-*.log", "Config in ~/.config/flowbox/  ·  Logs in /tmp/flowbox-*.log"))
        hint.font = .systemFont(ofSize: 10.5, weight: .regular)
        hint.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.78)
        linkInner.addArrangedSubview(hint)

        let linkCard = cardBox(containing: linkInner)
        stack.addArrangedSubview(linkCard)
        linkCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Footer copyright
        let copyright = NSTextField(labelWithString: L10n.tr("© 2026 FlowBox  ·  Crafted with care for macOS 13+  ·  保持简洁，保持高效", "© 2026 FlowBox  ·  Crafted with care for macOS 13+  ·  Keep it simple, keep it efficient"))
        copyright.font = .systemFont(ofSize: 10, weight: .regular)
        copyright.textColor = NSColor.tertiaryLabelColor
        copyright.alignment = .center
        stack.addArrangedSubview(copyright)
        copyright.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        aboutTab.view = aboutView
        tabView.addTabViewItem(aboutTab)
    }

    @objc private func openConfigFolder() {
        let url = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/flowbox")
        NSWorkspace.shared.open(url)
    }

    @objc private func openLogFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/tmp"))
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        let val = idx == 1 ? "zh" : idx == 2 ? "en" : "system"
        var cfg = AppConfig.load()
        cfg.language = val
        cfg.write()
        L10n.cachedLanguage = AppLanguage(rawValue: val) ?? .system
        let alert = NSAlert()
        alert.messageText = L10n.tr("语言已切换", "Language Changed")
        alert.informativeText = L10n.tr("将自动重启以应用新语言。", "FlowBox will restart automatically to apply the new language.")
        alert.addButton(withTitle: L10n.tr("立即重启", "Restart Now"))
        alert.addButton(withTitle: L10n.tr("稍后", "Later"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            relaunchApp()
        }
    }

    private func relaunchApp() {
        let url = Bundle.main.bundleURL
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "sleep 0.5; open \"" + url.path + "\""]
        try? proc.run()
        NSApp.terminate(nil)
    }

    @objc private func copyVersionInfo() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? version
        let info = "FlowBox \(version) (\(build)) - net.ai2048.flowbox - macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(info, forType: .string)
        // subtle feedback via status: use NSSound or toast could be added
        NSSound(named: .init("Pop"))?.play()
    }
}
