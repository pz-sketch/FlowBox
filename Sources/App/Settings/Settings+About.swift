import AppKit
import SharedCore
import os

extension SettingsWindowController {
    func buildAboutTab(tabView: NSTabView) {
        let stack = UIStyle.makeTab(tabView, identifier: "about", label: L10n.tr("关于", "About"), spacing: UIStyle.Metrics.sp16)

        // ========== 品牌区 ==========
        let hero = UIStyle.hStack(spacing: UIStyle.Metrics.sp14)

        let iconBox = NSView()
        iconBox.wantsLayer = true
        iconBox.layer?.cornerRadius = UIStyle.Metrics.radiusL
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
            iconView.contentTintColor = UIStyle.Palette.accent
            iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
        }
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(iconView)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: iconBox.leadingAnchor, constant: UIStyle.Metrics.sp6),
            iconView.trailingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: -UIStyle.Metrics.sp6),
            iconView.topAnchor.constraint(equalTo: iconBox.topAnchor, constant: UIStyle.Metrics.sp6),
            iconView.bottomAnchor.constraint(equalTo: iconBox.bottomAnchor, constant: -UIStyle.Metrics.sp6),
        ])
        hero.addArrangedSubview(iconBox)

        let titleStack = UIStyle.vStack(spacing: UIStyle.Metrics.sp4 - 1)
        titleStack.addArrangedSubview(UIStyle.label("FlowBox", font: UIStyle.Text.hero(), color: UIStyle.Palette.text))
        titleStack.addArrangedSubview(UIStyle.label(
            L10n.tr("极简工具箱 — 轻量 · 高效 · 不打扰", "FlowBox — Lightweight · Efficient · Unobtrusive"),
            font: UIStyle.Text.caption(), color: UIStyle.Palette.textSecondary))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        titleStack.addArrangedSubview(UIStyle.label(
            L10n.tr("版本", "Version") + " \(version)  ·  net.ai2048.flowbox",
            font: UIStyle.Text.mono(10), color: UIStyle.Palette.textTertiary))
        hero.addArrangedSubview(titleStack)
        hero.addArrangedSubview(UIStyle.spacer())
        stack.addArrangedSubview(hero)
        UIStyle.fillWidth(hero, in: stack)

        // ========== 界面语言 ==========
        stack.addArrangedSubview(sectionHeader(
            L10n.tr("界面语言", "Language"),
            subtitle: L10n.tr("切换后重启生效", "Restart to apply after switching"),
            symbol: "globe"
        ))
        let langRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp12)
        let langIcon = NSImageView(image: NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage())
        langIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        langIcon.contentTintColor = UIStyle.Palette.accent
        langRow.addArrangedSubview(langIcon)
        langRow.addArrangedSubview(UIStyle.label(
            L10n.tr("界面语言", "Language"),
            font: UIStyle.Text.title(), color: UIStyle.Palette.text))
        let langPop = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
        langPop.addItems(withTitles: [L10n.tr("跟随系统", "Follow System"), "中文", "English"])
        let current = AppConfig.load().language
        if current == "en" { langPop.selectItem(at: 2) } else if current == "zh" { langPop.selectItem(at: 1) } else { langPop.selectItem(at: 0) }
        langPop.target = self
        langPop.action = #selector(languageChanged(_:))
        langPop.controlSize = .regular
        langPop.font = UIStyle.Text.title()
        langRow.addArrangedSubview(langPop)
        langRow.addArrangedSubview(UIStyle.label(
            L10n.tr("重启后生效", "Restart to apply"),
            font: UIStyle.Text.caption(), color: UIStyle.Palette.textSecondary))
        let langCard = cardBox(containing: langRow)
        stack.addArrangedSubview(langCard)
        UIStyle.fillWidth(langCard, in: stack)

        // ========== 功能一览 ==========
        stack.addArrangedSubview(sectionHeader(
            L10n.tr("功能一览", "Features"),
            subtitle: L10n.tr("为 Finder 与创作流程做小而美的增强", "Small, beautiful enhancements for Finder & creation"),
            symbol: "star.circle"
        ))
        let featInner = UIStyle.vStack(spacing: UIStyle.Metrics.sp10)
        let features: [(String, String)] = [
            ("list.bullet.indent", L10n.tr("右键增强 — 复制路径 / 终端打开 / 新建文件模板", "Finder tweak — Copy path / Open in Terminal / New file from template")),
            ("computermouse", L10n.tr("鼠标增强 — 外接鼠标滚轮反向 / 平滑惯性滚动", "Mouse — Reverse wheel / Smooth inertial scrolling")),
            ("camera.viewfinder", L10n.tr("框选截图 — 画笔 / 马赛克 / 文字 / 形状 / 复制保存", "Screenshot — Pen / Mosaic / Text / Shapes / Copy & Save")),
            ("video.badge.waveform", L10n.tr("全屏录屏 — 系统声音 / 麦克风 / 摄像头画中画", "Recording — System audio / Mic / Camera PiP")),
            ("shield.lefthalf.filled", L10n.tr("去隔离 — 拖入 .app/.dmg/.pkg 一键清理 quarantine", "De-Quarantine — Drop .app/.dmg/.pkg to strip quarantine")),
            ("menubar.rectangle", L10n.tr("菜单栏收纳 — 刘海/空间不足时收纳右侧图标", "Menu Bar — Collapse overflow icons behind notch")),
        ]
        for (sym, text) in features {
            let row = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
            let iv = NSImageView(image: NSImage(systemSymbolName: sym, accessibilityDescription: nil) ?? NSImage())
            iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            iv.contentTintColor = UIStyle.Palette.accent
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: 14).isActive = true
            row.addArrangedSubview(iv)
            let lb = UIStyle.label(text, font: UIStyle.Text.caption(), color: UIStyle.Palette.text)
            lb.lineBreakMode = .byWordWrapping
            row.addArrangedSubview(lb)
            featInner.addArrangedSubview(row)
        }
        let featCard = cardBox(containing: featInner)
        stack.addArrangedSubview(featCard)
        UIStyle.fillWidth(featCard, in: stack)

        // ========== 链接与支持 ==========
        stack.addArrangedSubview(sectionHeader(
            L10n.tr("链接与支持", "Links & Support"),
            subtitle: L10n.tr("配置、反馈与开源", "Config, feedback & open source"),
            symbol: "link.circle"
        ))
        let linkInner = UIStyle.vStack(spacing: UIStyle.Metrics.sp10)
        let btnRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        btnRow.addArrangedSubview(UIStyle.secondaryButton(
            L10n.tr("打开配置文件夹", "Open Config Folder"), symbol: "folder",
            target: self, action: #selector(openConfigFolder)))
        btnRow.addArrangedSubview(UIStyle.secondaryButton(
            L10n.tr("打开日志", "Open Logs"), symbol: "doc.text",
            target: self, action: #selector(openLogFolder)))
        btnRow.addArrangedSubview(UIStyle.secondaryButton(
            L10n.tr("复制版本信息", "Copy Version"), symbol: "doc.on.doc",
            target: self, action: #selector(copyVersionInfo)))
        linkInner.addArrangedSubview(btnRow)
        linkInner.addArrangedSubview(UIStyle.hint(
            L10n.tr("配置文件位于 ~/.config/flowbox/  ·  日志在 /tmp/flowbox-*.log", "Config in ~/.config/flowbox/  ·  Logs in /tmp/flowbox-*.log"),
            color: UIStyle.Palette.textSecondary.withAlphaComponent(0.78), maxWidth: 460, lines: 2))
        let linkCard = cardBox(containing: linkInner)
        stack.addArrangedSubview(linkCard)
        UIStyle.fillWidth(linkCard, in: stack)

        // ========== 版权 ==========
        let copyright = UIStyle.label(
            L10n.tr("© 2026 FlowBox  ·  Crafted with care for macOS 13+  ·  保持简洁，保持高效", "© 2026 FlowBox  ·  Crafted with care for macOS 13+  ·  Keep it simple, keep it efficient"),
            font: UIStyle.Text.footnote(), color: UIStyle.Palette.textTertiary)
        copyright.alignment = .center
        stack.addArrangedSubview(copyright)
        UIStyle.fillWidth(copyright, in: stack)
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
        NSSound(named: .init("Pop"))?.play()
    }
}
