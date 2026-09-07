import AppKit
import os
import SharedCore

/// 菜单栏溢出收纳:只保留一个箭头「«」常驻最右侧。
/// - 点箭头:弹出二级菜单,列出当前被刘海/空间不足挤掉的图标(带应用名与图标),点条目即触发它
final class MenuBarHider: NSObject {

    static let shared = MenuBarHider()

    private var arrowItem: NSStatusItem?
    /// 宿主 App 自己的主图标(AppDelegate 创建),按窗口号排除出二级菜单
    weak var mainStatusItem: NSStatusItem?
    private(set) var enabled = false
    private var cachedHidden: [HiddenInfo] = []
    /// 点击箭头直接取此快照(由 10s 轮询在后台计算),保证秒开
    private var hiddenCache: [HiddenInfo] = []
    private var hiddenCacheDate: Date?
    private var posCache: [PosEntry]?; private var posCacheDate: Date?
    private var iconCache: [String:(String,NSImage?)] = [:]

    /// 其他 App 的状态项窗口名/截图都受「屏幕录制」TCC 保护;没授权时只能显示编号
    var hasScreenCapturePermission: Bool {
        PermissionManager.isScreenCaptureTrusted
    }

    private let sanePositionRange: ClosedRange<Double> = 1...800

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        FlowLog.menuBar.info("MenuBarHider setEnabled=\(on)")
        if on {
            seedPositionsIfNeeded()
            createItems()
        } else {
            destroyItems()
        }
    }

    private func seedPositionsIfNeeded() {
        let d = UserDefaults.standard
        let arrowKey = "NSStatusItem Preferred Position FlowBoxMenuBarArrow"
        let mainKey = "NSStatusItem Preferred Position FlowBoxMainStatusItem"
        let arrowPos = d.double(forKey: arrowKey)
        var mainPos = d.double(forKey: mainKey)
        if !sanePositionRange.contains(mainPos) {
            mainPos = d.double(forKey: "NSStatusItem Preferred Position Item-0")
        }
        // 箭头要在主图标右边(值更小),且都在合理区间 — 验证后: Arrow 180 / Main 220 最右安全区
        let need = !sanePositionRange.contains(arrowPos)
            || (arrowPos != 0 && mainPos != 0 && !(arrowPos < mainPos))
        guard need || !sanePositionRange.contains(mainPos) else { return }
        d.set(180, forKey: arrowKey)
        d.set(220, forKey: mainKey)
    }

    private func createItems() {
        seedPositionsIfNeeded()
        let arrow = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        arrow.autosaveName = "FlowBoxMenuBarArrow"
        if let btn = arrow.button {
            btn.target = self
            btn.action = #selector(arrowClicked)
            let arrowLabel = L10n.tr("显示隐藏的菜单栏图标", "Show hidden menu bar icons")
            btn.image = NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: arrowLabel)
                ?? NSImage(systemSymbolName: "chevron.left", accessibilityDescription: arrowLabel)
            btn.setAccessibilityLabel(arrowLabel)
            btn.setAccessibilityHelp(L10n.tr("查看被刘海或空间挤掉的图标。", "View icons hidden by the notch or limited space."))
            btn.toolTip = arrowLabel
        }
        arrowItem = arrow
        startPollingHiddenIcons()
    }

    private func destroyItems() {
        stopPollingHiddenIcons()
        if let i = arrowItem { NSStatusBar.system.removeStatusItem(i) }
        arrowItem = nil
    }

    // MARK: - 10s 轮询预热(鼠标在菜单/箭头附近时暂停,避免 3→4 跳变)
    private var pollTimer: Timer?
    private var menuVisibleUntil: Date?
    private func isHoveringMenuOrArrow() -> Bool {
        // 1) NSMenu 正 popUp 时,系统不暴露 isVisible,直接用时间窗口判断
        if let until = menuVisibleUntil, Date() < until { return true }
        // 2) 鼠标在箭头热区(半径 ~60pt)也算悬停,避免刚弹出就被后台刷新重建
        if let btn = arrowItem?.button, let win = btn.window {
            let mouse = NSEvent.mouseLocation
            let frame = win.frame // status item window frame in screen coords
            let expanded = frame.insetBy(dx: -60, dy: -20)
            if expanded.contains(mouse) { return true }
        }
        return false
    }
    private func startPollingHiddenIcons() {
        stopPollingHiddenIcons()
        let refresh: () -> Void = { [weak self] in
            guard let self else { return }
            // 自愈: 箭头意外丢失(比如上次点了微信走腾位未恢复)则自动重建
            if self.enabled && self.arrowItem == nil {
                DispatchQueue.main.async { [weak self] in self?.restoreArrow(after: 0) }
            }
            if self.isHoveringMenuOrArrow() { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self else { return }
                _ = self.cachedPosEntries()
                let snap = self.buildHiddenList()
                DispatchQueue.main.async {
                    // 若用户正悬停/菜单可见,本次不写入,避免重建导致闪动或数量跳变
                    if self.isHoveringMenuOrArrow() { return }
                    self.hiddenCache = snap
                    self.hiddenCacheDate = Date()
                }
            }
        }
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in refresh() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
    }
    private func stopPollingHiddenIcons() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private var menuKeyMonitor: Any?

    // MARK: - 二级菜单

    @objc private func arrowClicked() {
        showHiddenMenuUsingCache()
    }

    /// 点击箭头:当场重建全量列表(pos/图标已有缓存,仅一次 CGWindowList 扫描,毫秒级),
    /// 保证"展示所有"——绝不使用过期快照导致少一个应用
    private func showHiddenMenuUsingCache() {
        let hidden = buildHiddenList()
        hiddenCache = hidden
        hiddenCacheDate = Date()
        cachedHidden = hidden
        let menu = NSMenu()
        if hidden.isEmpty {
            let it = NSMenuItem(title: L10n.tr("暂无被隐藏的图标(顶栏已全部可见)", "No hidden icons (all menu bar items are visible)"), action: nil, keyEquivalent: "")
            it.isEnabled = false
            menu.addItem(it)
        } else {
            for (idx, info) in hidden.enumerated() {
                let it = NSMenuItem(title: info.title, action: #selector(didPickHiddenItem(_:)), keyEquivalent: "")
                if let im = info.image { im.size = NSSize(width: 16, height: 16); it.image = im } else { it.image = nil }
                it.tag = idx
                it.target = self
                menu.addItem(it)
            }
        }
        // 下拉期间监听截图快捷键:按到即收回下拉并进入截屏
        let shotCfg = AppConfig.load().screenshot
        let shotCode = UInt16(shotCfg.hotKeyCode)
        let shotMods = shotCfg.hotKeyModifiers
        menuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var mods = 0
            if flags.contains(.command) { mods |= 256 }   // cmdKey
            if flags.contains(.option)  { mods |= 2048 }  // optionKey
            if flags.contains(.control) { mods |= 4096 }  // controlKey
            if flags.contains(.shift)   { mods |= 512 }   // shiftKey
            if event.keyCode == shotCode && mods == shotMods {
                menu.cancelTracking()
                if let m = self.menuKeyMonitor { NSEvent.removeMonitor(m); self.menuKeyMonitor = nil }
                DispatchQueue.main.async { ScreenshotSession.launch() }
                return nil
            }
            return event
        }
        // 冻结本次快照,避免菜单可见期间后台写入导致对同一次菜单数量跳变
        if let btn = arrowItem?.button, let view = btn.superview {
            let p = NSPoint(x: btn.frame.midX, y: btn.frame.minY - 4)
            menuVisibleUntil = Date().addingTimeInterval(4.0)
            menu.popUp(positioning: nil, at: p, in: view)
            menuVisibleUntil = Date().addingTimeInterval(0.6)
        } else if let btn = arrowItem?.button {
            menuVisibleUntil = Date().addingTimeInterval(4.0)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: btn.bounds.maxY + 6), in: btn)
            menuVisibleUntil = Date().addingTimeInterval(0.6)
        }
        if let m = menuKeyMonitor { NSEvent.removeMonitor(m); menuKeyMonitor = nil }
    }

    // 老入口保留给兼容(不再被调用)
    private func showHiddenMenu() { showHiddenMenuUsingCache() }

    @objc private func didPickOpenScreenCaptureSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    // 保留选择,点击箭头始终展示所有可列出的图标(空态也会显示)

    @objc private func didPickHiddenItem(_ sender: NSMenuItem) {
        guard cachedHidden.indices.contains(sender.tag) else { return }
        let info = cachedHidden[sender.tag]
        // 需求: 点击下拉里的应用 = 直接打开/激活该应用,不做任何顶栏腾挪
        if let bid = info.bundleID {
            for cand in launchBundleCandidates(for: bid) {
                // 已在运行: 直接激活，避免再 open helper 进程无反应
                if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier?.lowercased() == cand.lowercased() }) {
                    running.activate(options: [.activateAllWindows])
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cand) {
                        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                    }
                    return
                }
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cand) {
                    if cand.lowercased() != bid.lowercased() {
                        FlowLog.menuBar.info("直开 \(bid, privacy: .public) → \(cand, privacy: .public)")
                    }
                    NSWorkspace.shared.open(url)
                    return
                }
            }
            FlowLog.menuBar.info("未找到启动URL,退回腾位兜底 bid=\(bid, privacy: .public)")
        }
        // 极少数映射不到的应用才退回"腾位触发";成功后立即恢复箭头并回种位置
        squeezeOutAndTrigger(windowNumber: info.windowNumber)
    }

    /// helper 进程(如 com.bytedance.macos.feishu.helper)不能直接 open，需映射到主包
    private func launchBundleCandidates(for stored: String) -> [String] {
        let lower = stored.lowercased()
        let explicit: [String: String] = [
            "com.bytedance.macos.feishu.helper": "com.bytedance.macos.feishu",
            "com.bytedance.macos.feishu.helper.renderer": "com.bytedance.macos.feishu",
        ]
        if let mapped = explicit[lower] { return [mapped, stored] }
        if lower.hasSuffix(".helper") {
            return [String(stored.dropLast(".helper".count)), stored]
        }
        if let r = stored.range(of: ".helper", options: .caseInsensitive) {
            return [String(stored[..<r.lowerBound]), stored]
        }
        return [stored]
    }

    /// 移除箭头 → 目标窗口顶进可见区 → 点击 → 恢复箭头
    private func squeezeOutAndTrigger(windowNumber: CGWindowID, attempt: Int = 0) {
        if attempt == 0, let arrow = arrowItem {
            NSStatusBar.system.removeStatusItem(arrow)
            arrowItem = nil
            usleep(250_000)
        }
        // 最多重试 ~1.5s,直到目标窗口被系统重新排进可视区
        if isWindowOnscreen(windowNumber) {
            triggerStatusItem(windowNumber: windowNumber)
            restoreArrow(after: 0.4)
            return
        }
        if attempt < 6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.squeezeOutAndTrigger(windowNumber: windowNumber, attempt: attempt + 1)
            }
            return
        }
        // 始终没出现(比如仍超容量):直接按旧坐标点一次兜底,然后恢复箭头
        triggerStatusItem(windowNumber: windowNumber)
        restoreArrow(after: 0.2)
    }

    private func isWindowOnscreen(_ number: CGWindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        for w in list where (w[kCGWindowNumber as String] as? Int) == Int(number) {
            return (w[kCGWindowIsOnscreen as String] as? Bool) == true
        }
        return false
    }

    /// 把箭头状态项重新注册回菜单栏(位置值还在 defaults 里,会回到原来偏右的资深位)
    private func restoreArrow(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.arrowItem == nil, self.enabled else { return }
            self.createItems()
        }
    }

    private struct HiddenInfo {
        let windowNumber: CGWindowID
        let title: String
        let image: NSImage?
        var bundleID: String? = nil
    }

    private func hiddenStatusWindows() -> [HiddenInfo] { buildHiddenList() }

    private func buildHiddenList() -> [HiddenInfo] {
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownNumbers: Set<Int> = [
            arrowItem?.button?.window?.windowNumber,
            mainStatusItem?.button?.window?.windowNumber,
        ].compactMap { $0 }.reduce(into: Set<Int>()) { $0.insert($1) }

        // 无屏幕录制权限时拿不到窗口名(全空),名字前缀过滤失效,但 ownNumbers 仍然有效
        struct Win { let num: Int; let x: CGFloat; let winName: String; let isOn: Bool? }
        var wins: [Win] = []
        for w in list {
            guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "控制中心",
                  let layer = w[kCGWindowLayer as String] as? Int, layer == 25,
                  let num = w[kCGWindowNumber as String] as? Int else { continue }
            if ownNumbers.contains(num) { continue }
            let b = w[kCGWindowBounds as String] as? [String: Any]
            let x = (b?["X"] as? CGFloat) ?? (b?["X"] as? Double).map { CGFloat($0) } ?? 0
            let winName = w[kCGWindowName as String] as? String ?? ""
            // FlowBox 的三个窗口用名字过滤更稳(主图标的 windowNumber 不在 hider 里)
            if winName.hasPrefix("FlowBox") { continue }
            let isOn = w[kCGWindowIsOnscreen as String] as? Bool
            wins.append(Win(num: num, x: x, winName: winName, isOn: isOn))
        }

        // 通用第三方 Item-0 用位置排序精确映射到应用名/图标;具名窗口(WiFi/Battery 等)直接用窗口名
        // 关键: 只保留"正在运行"的域参与映射 — 已退出应用在 defaults 里残留位置键,
        // 会把窗口↔条目对齐挤偏,导致把别人的隐藏窗口错安成微信等可见应用的名字
        let runningBIDs = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        let allEntries = cachedPosEntries().filter { entry in
            if entry.domain == "net.ai2048.flowbox" { return false }
            let d = entry.domain.lowercased()
            if d.hasPrefix("com.apple.") { return true } // 系统常驻(TextInputMenuAgent/Spotlight 等)
            return runningBIDs.contains(d)
        }
        // 同一域多键去重,保最小值(最靠右那个生效)
        var seenDomains = Set<String>()
        let allEntriesDedup = allEntries.filter { e in
            if seenDomains.contains(e.domain) { return false }
            seenDomains.insert(e.domain)
            return true
        }
        // 仅 Item-0 的第三方条目用于通用映射
        var genericEntries = allEntriesDedup.filter { $0.key == "NSStatusItem Preferred Position Item-0" }
        genericEntries.sort { $0.value < $1.value }
        var genericWins = wins.filter { $0.winName == "Item-0" }
        genericWins.sort { $0.x > $1.x }
        var numToGeneric: [Int: PosEntry] = [:]
        // 双序列右对右 zip: x 越大(越靠右)对应 pos 越小(越靠右)
        // 数量必须完全一致才可信;差一个都会整体错位(把 A 的窗口安成 B 的名字,出现"顶栏微信+下拉微信")
        let gCount = min(genericWins.count, genericEntries.count)
        let exactAlign = genericWins.count == genericEntries.count
        for i in 0..<gCount {
            numToGeneric[genericWins[i].num] = genericEntries[i]
        }
        if !exactAlign {
            FlowLog.menuBar.info("窗口数\(genericWins.count)≠键数\(genericEntries.count),标题降级为纯图标")
        }

        // 具名条目按窗口名直接匹配(如 WiFi/Battery/BentoBox),不参与通用排序
        var nameToEntry: [String: PosEntry] = [:]
        for e in allEntries where e.key != "NSStatusItem Preferred Position Item-0" {
            let short = e.key.replacingOccurrences(of: "NSStatusItem Preferred Position ", with: "")
            nameToEntry[short] = e
        }

        var out: [HiddenInfo] = []
        for w in wins {
            if w.isOn == true { continue }
            var title: String
            var img: NSImage?
            if w.winName == "Item-0" {
                // 窗口真实截图图标为主(已有屏幕录制权限,截得到);名字仅在数量精确对齐时显示
                var cgImg: NSImage? = nil
                if let cg = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(w.num), [.boundsIgnoreFraming, .bestResolution]) {
                    cgImg = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width)/2, height: CGFloat(cg.height)/2))
                    cgImg?.isTemplate = false
                    cgImg?.size = NSSize(width: 18, height: 18)
                }
                if let e = numToGeneric[w.num] {
                    let info = appDisplayInfo(for: e.domain)
                    title = info.title
                    img = cgImg ?? info.icon
                } else {
                    // 映射对不上（通常是已退出应用的残留窗口）：直接跳过，不显示 图标xxx
                    continue
                }
            } else if w.winName.isEmpty {
                // 空名匿名窗口且无映射：跳过不展示，避免 图标xxx
                continue
            } else {
                // 具名系统图标:直接用窗口名,图标用控制中心内置或留空
                title = w.winName
                img = nil
            }
            if title.hasPrefix("FlowBox") { continue }
            var bid: String? = nil
            if w.winName == "Item-0", let e = numToGeneric[w.num] { bid = e.domain }
            out.append(HiddenInfo(windowNumber: CGWindowID(w.num), title: title, image: img, bundleID: bid))
            if out.count >= 16 { break }
        }
        return out
    }


    private func appDisplayInfo(for bundleID: String) -> (title: String, icon: NSImage?) {
        let lk=bundleID.lowercased()
        if let hit=iconCache[lk] { return hit }

        let lower = bundleID.lowercased()
        // helper 进程的 display name 常是英文(如 Lark Helper),映射成用户认识的产品名
        let prettyNames: [String: String] = [
            "com.bytedance.macos.feishu.helper": "飞书",
            "com.bytedance.macos.feishu": "飞书",
            "com.tencent.xinWeChat": "微信",
            "com.alibaba.DingTalk": "钉钉",
            "com.tencent.WeWork": "企业微信",
            "cn.trae.app": "Trae",
            "io.github.clash-verge-rev.clash-verge-rev": "Clash Verge",
            "com.legendsec.vpnclientx": "奇安信VPN",
        ]
        if let pretty = prettyNames[lk] {
            var icon: NSImage? = nil
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                icon = NSWorkspace.shared.icon(forFile: url.path)
                icon?.size = NSSize(width: 16, height: 16)
            }
            let _vp=(pretty, icon); iconCache[lk]=_vp; return _vp
        }
        // 已知无点域或特殊
        let known: [String: (String, String?)] = [
            "com.caldis.mos": ("Mos", "/Applications/Mos.app"),
            "ndsc-gui": ("NDSC", "/Applications/ndsc-gui.app"),
            "cn.wps.wpscloudsvr": ("WPS 365", nil),
            "com.qianxin.tianqing": ("天擎", "/Applications/QI-ANXIN Tianqing.app"),
            "com.dbx.app": ("DBX", "/Applications/DBX.app"),
        ]
        if let (t, pp) = known[lower] {
            if let path = pp, FileManager.default.fileExists(atPath: path) {
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 16, height: 16)
                let _v=(t, icon); iconCache[lk]=_v; return _v
            } else if pp == nil {
                let _v0=(t, nil as NSImage?); iconCache[lk]=_v0; return _v0
            }
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let raw = FileManager.default.displayName(atPath: url.path)
            let title = raw.hasSuffix(".app") ? String(raw.dropLast(4)) : (raw.isEmpty ? (bundleID.components(separatedBy: ".").last ?? bundleID) : raw)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            let _v1=(title, icon); iconCache[lk]=_v1; return _v1
        }
        // 非标准: /Applications 模糊
        let candidates = (try? FileManager.default.contentsOfDirectory(atPath: "/Applications")) ?? []
        for name in candidates {
            let lname = name.lowercased()
            if lname.contains(lower) || lower.contains(lname.replacingOccurrences(of: ".app", with: "")) {
                let path = "/Applications/" + name
                let title = FileManager.default.displayName(atPath: path)
                let clean = title.hasSuffix(".app") ? String(title.dropLast(4)) : title
                let icon = NSWorkspace.shared.icon(forFile: path)
                icon.size = NSSize(width: 16, height: 16)
                if !clean.isEmpty { let _v2=(clean, icon); iconCache[lk]=_v2; return _v2 }
            }
        }
        return (bundleID.components(separatedBy: ".").last ?? bundleID, nil)
    }

    private func triggerStatusItem(windowNumber: CGWindowID) {
        // 展开后重新查表拿新坐标再点,避免用旧的负坐标/刘海下坐标
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return }
        for w in list where (w[kCGWindowNumber as String] as? Int) == Int(windowNumber) {
            if let b = w[kCGWindowBounds as String] as? [String: Any],
               let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
               let wd = b["Width"] as? CGFloat, let ht = b["Height"] as? CGFloat {
                // CG y 是从屏幕左上角算,需翻到 Cocoa 坐标再发 CGEvent
                let screenH = NSScreen.screens.first?.frame.height ?? 900
                let pt = CGPoint(x: x + wd/2, y: screenH - (y + ht/2))
                // 若仍不可见(仍被刘海挡),提示用户用"固定到右侧"
                if x < 0 || x > 1600 {
                    FlowLog.menuBar.info("触发隐藏图标 window \(windowNumber) 仍在屏幕外 x=\(x),建议固定到右侧")
                }
                let src = CGEventSource(stateID: .combinedSessionState)
                CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
                usleep(80_000)
                CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
                return
            }
        }
    }


    private struct PosEntry { let domain: String; let key: String; let value: Double }

    private func cachedPosEntries() -> [PosEntry] {
        if let c=posCache, let d=posCacheDate, Date().timeIntervalSince(d)<8 { return c }
        let fresh = allPreferredUncached()
        posCache=fresh; posCacheDate=Date(); return fresh
    }
    private func allPreferredUncached() -> [PosEntry] {

        // 用 defaults find 文本解析最稳,避免 CFPreferences 跨容器问题
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        task.arguments = ["find", "NSStatusItem Preferred Position"]
        let pipe = Pipe()
        task.standardOutput = pipe
        // defaults find 把错误打到 stderr,合并
        let errPipe = Pipe()
        task.standardError = errPipe
        try? task.run()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let txt = String(data: data, encoding: .utf8) ?? ""
        var out: [PosEntry] = []
        var curDomain = ""
        for line in txt.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("Found") && t.contains("domain '") {
                // Found 1 keys in domain 'cn.trae.app':
                if let r = t.range(of: "domain '"), let e = t[r.upperBound...].firstIndex(of: "'") {
                    curDomain = String(t[r.upperBound..<e])
                }
            } else if t.contains("NSStatusItem Preferred Position") && t.contains("=") {
                // "NSStatusItem Preferred Position Item-0" = 770;
                let parts = t.components(separatedBy: "=")
                guard parts.count == 2 else { continue }
                let keyPart = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                let valPart = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
                if let v = Double(valPart) {
                    out.append(PosEntry(domain: curDomain, key: keyPart, value: v))
                }
            }
        }
        return out
    }
    private func allPreferredPositionEntries() -> [PosEntry] { cachedPosEntries() }
}
