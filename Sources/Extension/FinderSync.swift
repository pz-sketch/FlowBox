import AppKit
import FinderSync
import SharedCore

final class FinderSync: FIFinderSync {

    /// 菜单打开时算好的「进入上级目录」落点,供 actGoUp 取用。
    /// 不能靠菜单项的 representedObject 传递:它过不去 Finder 的 XPC 边界,点击时是 nil。
    private var pendingGoUpDestination: URL?

    override init() {
        super.init()
        // 把根目录注册为同步根,保证在任意位置右键都能出现菜单
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        syncConfigToHostIfNeeded()
    }

    /// 新配置位置(~/Library/Application Support/FlowBox/)还没有文件时,
    /// 把本容器里的旧配置经 flowbox://cfgsync 递给宿主写盘。
    /// macOS 27 起宿主无法读写扩展容器,旧配置只有本扩展读得到;
    /// 宿主可能未运行,NSWorkspace 会借这条 URL 顺便把它拉起。
    private func syncConfigToHostIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: ConfigStore.configURL.path),
              let data = try? Data(contentsOf: ConfigStore.extContainerConfigURL),
              let url = RCCommand.configSync(data: data.base64EncodedString()) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - 右键菜单

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        // Finder 只显示菜单的代理、不回扩展进程做启用验证,
        // 必须关掉自动禁用,否则菜单项点击无响应
        // (顺带重试配置递送:宿主此前未运行/未就绪时这里补一发)
        syncConfigToHostIfNeeded()
        let config = AppConfig.load()
        let menu = NSMenu(title: "FlowBox")
        menu.autoenablesItems = false

        func menuItem(_ title: String, _ action: Selector, tag: Int = 0) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.isEnabled = true
            item.tag = tag
            return item
        }

        if config.menu.copyFolder {
            menu.addItem(menuItem(L10n.tr("复制当前目录路径", "Copy Folder Path"), #selector(actCopyFolder)))
        }

        if config.menu.copySelection {
            let copySel = menuItem(L10n.tr("复制所选文件路径", "Copy Selection Paths"), #selector(actCopySelection))
            copySel.isEnabled = !(FIFinderSyncController.default().selectedItemURLs()?.isEmpty ?? true)
            menu.addItem(copySel)
        }

        if config.menu.openTerminal {
            menu.addItem(menuItem(L10n.tr("在终端中打开", "Open in Terminal"), #selector(actTerminal)))
        }

        if config.menu.goUp {
            // 落点在菜单构造时算好(此刻才取得到 targetedURL),点击时取用。
            // targetedURL 始终是窗口浏览的目录,与右键位置无关(实机验证),
            // 所以不必按 menuKind 分支,直接取其父目录。
            pendingGoUpDestination = EnclosingFolder.destination(
                target: FIFinderSyncController.default().targetedURL()
            )
            let goUp = menuItem(L10n.tr("进入上级目录", "Enclosing Folder"), #selector(actGoUp))
            goUp.isEnabled = pendingGoUpDestination != nil
            menu.addItem(goUp)
        }

        if config.menu.newFile {
            let subMenu = NSMenu(title: L10n.tr("新建文件", "New File"))
            subMenu.autoenablesItems = false
            for (index, template) in config.newFiles.enumerated() where template.enabled {
                subMenu.addItem(menuItem(template.displayName, #selector(actNewFile), tag: index))
            }
            if subMenu.items.isEmpty {
                subMenu.addItem(withTitle: L10n.tr("(没有启用的模板)", "(No enabled templates)"), action: nil, keyEquivalent: "")
            }
            let parent = NSMenuItem(title: L10n.tr("新建文件", "New File"), action: nil, keyEquivalent: "")
            parent.isEnabled = true
            parent.submenu = subMenu
            menu.addItem(parent)
        }

        let hasSel = !(FIFinderSyncController.default().selectedItemURLs()?.isEmpty ?? true)
        if hasSel {
            menu.addItem(menuItem(L10n.tr("去除隔离属性(xattr)", "Remove Quarantine (xattr)"), #selector(actStripQuarantine)))
        }

        return menu
    }

    // MARK: - 目标目录

    /// 右键的是单个文件夹时用该文件夹,否则用 Finder 当前浏览的目录。
    /// 右键若选了文件,则取其所在目录,以便“在终端中打开/新建文件”始终有目录可用。
    private func targetDirectory() -> URL? {
        if let selected = FIFinderSyncController.default().selectedItemURLs(),
           selected.count == 1 {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: selected[0].path, isDirectory: &isDir) {
                if isDir.boolValue { return selected[0] }
                // 选的是文件 → 取父目录
                return selected[0].deletingLastPathComponent()
            }
        }
        if let targeted = FIFinderSyncController.default().targetedURL() {
            return targeted
        }
        // 兜底:桌面或无目标目录时落在主目录,避免“没反应”的错觉
        return URL(fileURLWithPath: NSHomeDirectory())
    }

    /// 把命令转发给宿主 App 执行(沙盒内的扩展只负责菜单与取路径)
    private func dispatch(_ url: URL?) {
        guard let url = url else {
            NSLog("[FlowBox] 命令 URL 构造失败")
            return
        }
        let ok = NSWorkspace.shared.open(url)
        NSLog("[FlowBox] 已派发 \(url.host ?? "?") → 宿主App \(ok ? "成功" : "失败")")
    }

    // MARK: - 动作

    @objc func actCopyFolder() {
        NSLog("[FlowBox] 点击:复制当前目录路径")
        guard let dir = FIFinderSyncController.default().targetedURL() else { return }
        dispatch(RCCommand.copy(text: dir.path))
    }

    @objc func actCopySelection() {
        NSLog("[FlowBox] 点击:复制所选文件路径")
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else {
            return
        }
        dispatch(RCCommand.copy(text: urls.map(\.path).joined(separator: "\n")))
    }

    @objc func actTerminal() {
        NSLog("[FlowBox] 点击:在终端中打开")
        guard let dir = targetDirectory() else { return }
        dispatch(RCCommand.terminal(dir: dir.path))
    }

    @objc func actGoUp() {
        NSLog("[FlowBox] 点击:进入上级目录")
        // 落点在 menu(for:) 里算好(targetedURL 只在菜单构造/动作回调里有效),这里取用
        guard let destination = pendingGoUpDestination else {
            NSLog("[FlowBox] 已无上级可去(根目录或未取到目标)")
            return
        }
        pendingGoUpDestination = nil
        dispatch(RCCommand.goUp(dir: destination.path))
    }

    @objc func actNewFile(_ sender: NSMenuItem) {
        NSLog("[FlowBox] 点击:新建文件 #\(sender.tag)")
        guard let dir = targetDirectory() else { return }
        dispatch(RCCommand.newFile(dir: dir.path, index: sender.tag))
    }

    @objc func actStripQuarantine() {
        NSLog("[FlowBox] 点击:去除隔离属性")
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return }
        dispatch(RCCommand.stripQuarantine(paths: urls.map(\.path)))
    }
}
