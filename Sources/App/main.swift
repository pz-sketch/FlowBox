import AppKit
import SharedCore

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private let settings = SettingsWindowController()
    private var screenshotItem: NSMenuItem!
    private var recordingItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 单实例保护:已有实例在运行时直接退出(两个实例会各自拦截滚轮、正反抵消)
        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                NSLog("[FlowBox] 检测到已有实例(pid \(others.first!.processIdentifier)),当前实例退出")
                exit(0)
            }
        }

        // 首次启动时写入默认配置
        _ = AppConfig.load()

        // 上次开启了滚轮功能的话,启动时恢复(未授权时会静默失败,重新打开开关即可)
        let scroll = AppConfig.load().scroll
        ScrollReverser.shared.reverseEnabled = scroll.reverseMouseWheel
        ScrollReverser.shared.smoothEnabled = scroll.smoothScrolling
        ScrollReverser.shared.minStep = scroll.minStep
        if scroll.reverseMouseWheel || scroll.smoothScrolling {
            if !ScrollReverser.shared.start(), !PermissionManager.isEffectivelyTrusted {
                // 启动时静默:不弹系统授权框(避免每次重启都弹),只打日志提示用户去设置页手动开启
                NSLog("[FlowBox] 滚轮引擎启动失败,等待用户在设置中授权后手动开启")
            }
        }

        // 上次开启了菜单栏收纳的话,恢复分隔线和箭头
        if AppConfig.load().menuBar.hiderEnabled {
            MenuBarHider.shared.setEnabled(true)
        }

        // 人脸看守:按上次配置启停(未授权时静默,watching 停留在 waitingPermission)
        if AppConfig.load().presence.enabled {
            PresenceMonitor.shared.refresh()
        }

        // 截图/录屏:注册全局快捷键(Carbon 方案,无需辅助功能权限)
        let shot = AppConfig.load().screenshot
        HotKeyCenter.shared.onTrigger = { ScreenshotSession.launch() }
        if HotKeyCenter.shared.register(
            keyCode: UInt32(shot.hotKeyCode),
            modifiers: UInt32(shot.hotKeyModifiers),
            kind: .screenshot
        ) {
            shotDebugLog("截图快捷键注册成功:\(HotKeyCenter.comboName(keyCode: UInt32(shot.hotKeyCode), modifiers: UInt32(shot.hotKeyModifiers)))")
        } else {
            shotDebugLog("截图快捷键注册失败(可能被其它应用占用),可在设置 → 截图中更换")
        }
        let rec = AppConfig.load().recording
        HotKeyCenter.shared.onRecordTrigger = { Task { @MainActor in ScreenRecorder.shared.toggle() } }
        if HotKeyCenter.shared.register(
            keyCode: UInt32(rec.hotKeyCode),
            modifiers: UInt32(rec.hotKeyModifiers),
            kind: .recording
        ) {
            shotDebugLog("录屏快捷键注册成功:\(HotKeyCenter.comboName(keyCode: UInt32(rec.hotKeyCode), modifiers: UInt32(rec.hotKeyModifiers)))")
        } else {
            shotDebugLog("录屏快捷键注册失败(可能被占用),可在设置中更换")
        }

        // 接收扩展通过 URL scheme 发来的命令
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // 持久化图标位置,避免被菜单栏溢出机制挤出
        statusItem.autosaveName = "FlowBoxMainStatusItem"
        if let button = statusItem.button {
            button.image =
                NSImage(
                    systemSymbolName: "contextualmenu.and.cursorarrow",
                    accessibilityDescription: L10n.tr("极简工具箱", "FlowBox")
                )
                ?? NSImage(systemSymbolName: "gearshape", accessibilityDescription: L10n.tr("极简工具箱", "FlowBox"))
            button.toolTip = L10n.tr("极简工具箱", "FlowBox")
        }
        // 主图标也要从「被隐藏图标」清单里排除
        MenuBarHider.shared.mainStatusItem = statusItem

        let menu = NSMenu()
        menu.delegate = self

        screenshotItem = menuItem(L10n.tr("截屏", "Screenshot"), symbol: "camera.viewfinder", action: #selector(takeScreenshot))
        menu.addItem(screenshotItem)

        recordingItem = menuItem(L10n.tr("录屏", "Recording"), symbol: "record.circle", action: #selector(toggleRecording))
        menu.addItem(recordingItem)

        menu.addItem(menuItem(L10n.tr("录屏转 GIF…", "Recording → GIF…"), symbol: "photo.on.rectangle.angled", action: #selector(convertRecordingToGif)))

        menu.addItem(menuItem(L10n.tr("去隔离…", "De-Quarantine…"), symbol: "checkmark.shield", action: #selector(openQuarantinePanel)))
        menu.addItem(menuItem(L10n.tr("设置…", "Settings…"), symbol: "gearshape", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(menuItem(L10n.tr("打开配置文件(JSON)", "Open Config (JSON)"), symbol: "doc.text", action: #selector(openConfig)))
        menu.addItem(menuItem(L10n.tr("使用说明", "Help"), symbol: "questionmark.circle", action: #selector(showHelp)))

        menu.addItem(NSMenuItem.separator())

        menu.addItem(menuItem(L10n.tr("启用扩展(打开系统设置)", "Enable Extension (System Settings)"), symbol: "puzzlepiece", action: #selector(enableExtension)))

        menu.addItem(NSMenuItem.separator())

        // 退出走响应链到 NSApplication,不设 target
        let quit = menu.addItem(
            withTitle: L10n.tr("退出", "Quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        if let image = NSImage(systemSymbolName: "power", accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            quit.image = image
        }

        statusItem.menu = menu
    }

    /// 带小图标的菜单项(模板图标,自动适配深浅色)
    private func menuItem(
        _ title: String,
        symbol: String,
        action: Selector,
        keyEquivalent: String = ""
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        item.isEnabled = true
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            image.isTemplate = true
            image.size = NSSize(width: 16, height: 16)
            item.image = image
        }
        return item
    }

    // MARK: - URL 命令(来自 Finder 扩展)

    @objc private func handleGetURL(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: raw) else {
            NSLog("[FlowBox] 宿主:收到无法解析的 URL")
            return
        }
        CommandExecutor.perform(url)
    }

    // MARK: - 菜单动作

    @objc private func takeScreenshot() {
        ScreenshotSession.launch()
    }

    @objc private func toggleRecording() {
        Task { @MainActor in ScreenRecorder.shared.toggle() }
    }

    @objc private func convertRecordingToGif() {
        Task { @MainActor in GifConverter.shared.pickAndConvert() }
    }

    @objc private func openQuarantinePanel() {
        QuarantinePanel.shared.show()
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func enableExtension() {
        // 直达系统设置的扩展管理页
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(AppConfig.configURL)
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = L10n.tr("极简工具箱 — 使用说明", "FlowBox — Help")
        alert.informativeText = """
        1. 在 Finder 任意位置右键,即可看到「FlowBox」子菜单
        2. 功能:复制当前目录路径 / 复制所选文件路径 / 在终端中打开 / 新建文件
        3. 按快捷键(默认 ⌥A)框选截图:画笔 / 马赛克标注后 Enter 复制到剪贴板
        4. 点击菜单栏图标 →「设置…」可自定义功能、模板与截图快捷键,改动即时生效
        5. 菜单栏 →「录屏转 GIF…」可把录屏 .mov(或任意 mov/mp4)转成 GIF,帧率/宽度可选

        首次使用「在终端中打开」时,系统会弹一次「控制 Terminal」的授权,允许即可。
        首次截屏需授权「屏幕录制」,授权后重启本应用生效。
        设置 →「人脸」可开启离开自动锁屏(本地检测,不联网不存图;锁后仍需密码/Touch ID 解锁)。
        如果右键菜单没出现,试试重启 Finder。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }
}

/// 菜单打开时刷新截图/录屏项显示的快捷键与状态
extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let shot = AppConfig.load().screenshot
        screenshotItem.title = L10n.tr("截屏", "Screenshot") + "(\(HotKeyCenter.comboName(keyCode: UInt32(shot.hotKeyCode), modifiers: UInt32(shot.hotKeyModifiers))))"
        let rec = AppConfig.load().recording
        if ScreenRecorder.shared.isRecording {
            recordingItem.title = L10n.tr("■ 停止录制", "■ Stop Recording")
        } else if ScreenRecorder.shared.isCountingDown {
            recordingItem.title = L10n.tr("录屏(倒计时中…)", "Recording (countdown…)" )
        } else {
            recordingItem.title = L10n.tr("录屏", "Recording") + "(\(HotKeyCenter.comboName(keyCode: UInt32(rec.hotKeyCode), modifiers: UInt32(rec.hotKeyModifiers))))"
        }
    }
}

/// 执行扩展转发来的命令(宿主不受沙盒限制)
enum CommandExecutor {

    static func perform(_ url: URL) {
        guard url.scheme == RCCommand.scheme else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = (components?.queryItems ?? []).reduce(into: [String: String]()) {
            $0[$1.name] = $1.value
        }

        switch url.host {
        case "copy":
            if let text = query["text"] {
                paste(text)
            }
        case "shot":
            shotDebugLog("URL 命令触发截图\(query["tool"].map { ",工具=\($0)" } ?? "")")
            switch query["tool"] {
            case "mosaic": ScreenshotSession.launch(initialTool: .mosaic)
            case "text": ScreenshotSession.launch(initialTool: .text)
            default: ScreenshotSession.launch()
            }
        case "terminal":
            if let dir = query["dir"] {
                openTerminal(path: dir)
            }
        case "qxattr":
            if let raw = query["paths"] {
                let paths = raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
                QuarantineHelper.strip(paths: paths) { ok, fail in
                    let remains = paths.filter { QuarantineHelper.isQuarantined(path: $0) }
                    let alert = NSAlert()
                    if fail == 0, remains.isEmpty {
                        alert.messageText = L10n.tr("✅ 去隔离成功", "✅ De-Quarantined")
                        alert.informativeText = L10n.tr("\(ok) 项已清除,可直接打开:\n", "\(ok) items cleared, ready to open:\n") + paths.joined(separator: "\n")
                        alert.alertStyle = .informational
                    } else if remains.isEmpty {
                        alert.messageText = L10n.tr("✅ 去隔离完成", "✅ Done")
                        alert.informativeText = L10n.tr("成功 \(ok) 失败 \(fail)\n验证:无残留\n", "Success \(ok) Failed \(fail)\nVerified: no quarantine remains\n") + paths.joined(separator: "\n")
                    } else {
                        alert.messageText = L10n.tr("⚠️ 去隔离未完全成功", "⚠️ Partial Failure")
                        alert.informativeText = L10n.tr("成功 \(ok) 失败 \(fail)\n仍带隔离:\n", "Success \(ok) Failed \(fail)\nStill quarantined:\n") + remains.joined(separator: "\n") + L10n.tr("\n\n终端验证: xattr -p com.apple.quarantine \"路径\" (无输出即已清除)", "\n\nVerify: xattr -p com.apple.quarantine \"path\" (no output = cleared)")
                        alert.alertStyle = .warning
                    }
                    alert.runModal()
                }
            }
        case "newfile":
            if let dir = query["dir"], let index = query["index"].flatMap(Int.init) {
                createFile(index: index, in: URL(fileURLWithPath: dir))
            }
        default:
            NSLog("[FlowBox] 宿主:未知命令 \(url.host ?? "?")")
        }
    }

    // MARK: - 操作实现

    private static func paste(_ text: String) {
        NSLog("[FlowBox] 宿主:复制路径")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static func openTerminal(path: String) {
        NSLog("[FlowBox] 宿主:在终端打开 \(path)")
        var dir = path
        // 若传入的是文件,取其父目录
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), !isDir.boolValue {
            dir = (dir as NSString).deletingLastPathComponent
        }
        if dir.isEmpty { dir = NSHomeDirectory() }

        // 方案一: /usr/bin/open -a Terminal (无需“自动化”权限,最可靠)
        // 会在 Terminal 新开窗口并直接定位到该目录,不依赖 AppleScript
        do {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-a", "Terminal", dir]
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                NSLog("[FlowBox] open -a Terminal 成功: \(dir)")
                return
            }
            NSLog("[FlowBox] open -a Terminal 退出码 \(proc.terminationStatus),走 AppleScript 兜底")
        } catch {
            NSLog("[FlowBox] open -a Terminal 抛异常: \(error),走 AppleScript 兜底")
        }

        // 方案二: AppleScript 兜底(需要“自动化→控制 Terminal”权限,首次会弹框)
        let quoted = "'" + dir.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let shellCommand = "cd " + quoted + " && clear"
        let escaped = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error {
            NSLog("[FlowBox] AppleScript 打开终端也失败: \(error)")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = L10n.tr("打开终端失败", "Failed to open Terminal")
                alert.informativeText = L10n.tr(
                    "已尝试打开 \(dir) 但失败。\n请检查：1) 系统设置 → 隐私与安全 → 自动化 → 允许 FlowBox 控制 Terminal；2) Terminal 是否已安装。",
                    "Failed to open \(dir).\nPlease check: 1) System Settings → Privacy → Automation → allow FlowBox to control Terminal; 2) Terminal is installed."
                )
                alert.alertStyle = .warning
                alert.runModal()
            }
        } else {
            NSLog("[FlowBox] AppleScript 打开终端成功(兜底)")
        }
    }

    private static func createFile(index: Int, in directory: URL) {
        let templates = AppConfig.load().newFiles
        guard templates.indices.contains(index) else {
            NSLog("[FlowBox] 宿主:模板序号 \(index) 不存在")
            return
        }
        let template = templates[index]

        let baseName = (template.displayFilename as NSString).deletingPathExtension
        let ext = (template.displayFilename as NSString).pathExtension

        var url = directory.appendingPathComponent(template.filename)
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let name = ext.isEmpty ? "\(baseName) \(number)" : "\(baseName) \(number).\(ext)"
            url = directory.appendingPathComponent(name)
            number += 1
        }

        NSLog("[FlowBox] 宿主:新建文件 \(url.path)")
        do {
            let data: Data
            if template.isBase64, let decoded = Data(base64Encoded: template.content) {
                data = decoded
            } else if template.isBase64 {
                NSLog("[FlowBox] 宿主:模板 \(template.name) 的 base64 解码失败,写入空文件")
                data = Data()
            } else {
                data = template.content.data(using: .utf8) ?? Data()
            }
            try data.write(to: url, options: .atomic)
            // 在 Finder 中定位并选中刚创建的文件
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSLog("[FlowBox] 新建文件失败(\(url.path)): \(error.localizedDescription)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
