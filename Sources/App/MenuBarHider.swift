import AppKit
import os
import SharedCore

/// 菜单栏溢出收纳:只保留一个箭头「«」常驻最右侧。
/// - 点箭头:弹出二级菜单,列出当前被刘海/空间不足挤掉的图标,点条目即触发它
/// - 菜单位置交给系统托管(`statusItem.menu` + `NSMenuDelegate`),不再手动 `popUp` 定锚点
final class MenuBarHider: NSObject, NSMenuDelegate {

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
    /// 上一轮「主屏状态项窗口号」全集,用于识别显示拓扑瞬变(见 buildHiddenList 内的零交集检查)
    private var lastMainWinIDs: Set<Int> = []
    /// 窗口号 → 上次成功配到的身份。主屏匿名项的名字靠副屏镜像副本供给,副屏重连时那批
    /// 副本会整个重建(窗口号全换),重建完成前命名断供 —— 主屏窗口号此刻不变,用缓存顶着。
    private var identityCache: [CGWindowID: (title: String, bundleID: String?)] = [:]
    /// 状态项窗口缩略图缓存(键 = 窗口号)。
    ///
    /// ⚠️ 不要用 `CGWindowListCreateImage`:它在 macOS 15 起被标记 obsoleted,在 macOS 26 上
    /// 运行时对**任何**窗口都返回 nil(已用 dlsym 绕开编译期检查实测过,包括本进程自己的窗口)。
    /// 改走系统工具 `screencapture -x -o -l <windowID>`,它走的是同一套窗口服务器抓取但未被移除。
    /// 抓取在后台线程做(fork 子进程约 100ms/窗口),菜单展开时只读缓存 —— 菜单构建必须同步返回。
    private var thumbCache: [CGWindowID: NSImage] = [:]

    /// 其他 App 的状态项窗口名/截图都受「屏幕录制」TCC 保护;没授权时只能显示编号
    var hasScreenCapturePermission: Bool {
        PermissionManager.isScreenCaptureTrusted
    }

    private let sanePositionRange: ClosedRange<Double> = 1...800

    /// FlowBox 自己的 bundle id —— 主图标与扩展的状态项窗口一律不进下拉、也不当命名副本。
    private static let ownBundleIDs: Set<String> = ["net.ai2048.flowbox", ConfigStore.extBundleID]

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
            let arrowLabel = L10n.tr("显示隐藏的菜单栏图标", "Show hidden menu bar icons")
            btn.image = NSImage(systemSymbolName: "chevron.left.2", accessibilityDescription: arrowLabel)
                ?? NSImage(systemSymbolName: "chevron.left", accessibilityDescription: arrowLabel)
            btn.setAccessibilityLabel(arrowLabel)
            btn.setAccessibilityHelp(L10n.tr("查看被刘海或空间挤掉的图标。", "View icons hidden by the notch or limited space."))
            btn.toolTip = arrowLabel
        }
        // 位置由系统托管:AppKit 自己算菜单锚点并处理贴顶/贴边/刘海。
        // 手动 popUp 定锚点时,锚点一旦落在菜单栏内部,系统会把首项滚出视野并在菜单顶部画一个
        // 居中的 ^ 滚动指示器(鼠标滑进菜单后才复原)——交给系统就没有这个class的问题。
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false     // 条目启用状态由我们自己定,避免菜单弹出时再校验一轮
        arrow.menu = menu
        arrowItem = arrow
        startPollingHiddenIcons()
    }

    private func destroyItems() {
        stopPollingHiddenIcons()
        removeScreenshotHotKeyMonitor()
        isMenuOpen = false
        if let i = arrowItem {
            i.menu?.delegate = nil
            NSStatusBar.system.removeStatusItem(i)
        }
        arrowItem = nil
    }

    // MARK: - 10s 轮询预热(鼠标在菜单/箭头附近时暂停,避免 3→4 跳变)
    private var pollTimer: Timer?
    /// 菜单是否正展开(由 NSMenuDelegate 精确驱动,替代原来的时间窗口猜测)
    private var isMenuOpen = false
    private func isHoveringMenuOrArrow() -> Bool {
        // 1) 菜单展开期间一律不刷新,避免后台重建导致条目闪动或数量跳变
        if isMenuOpen { return true }
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
                    self.warmThumbCache()
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

    // MARK: - 二级菜单(交给系统托管)

    /// 菜单每次展开前重建全量列表(pos/图标已有缓存,仅一次 CGWindowList 扫描,毫秒级),
    /// 保证"展示所有"——绝不使用过期快照导致少一个应用
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hidden = buildHiddenList()
        hiddenCache = hidden
        hiddenCacheDate = Date()
        cachedHidden = hidden
        if hidden.isEmpty {
            let text = L10n.tr("暂无被隐藏的图标(顶栏已全部可见)", "No hidden icons (all menu bar items are visible)")
            let row = MenuRowView(title: text, icon: nil, isEnabled: false)
            row.frame.size.width = MenuRowView.unifiedWidth(forTitles: [text])
            let it = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            it.isEnabled = false
            it.view = row
            menu.addItem(it)
            return
        }
        // 行整行自绘 —— 选中态要「蓝底白字」,系统在未激活菜单里只会给一枚浅紫胶囊(见 MenuRowView)
        let rowWidth = MenuRowView.unifiedWidth(forTitles: hidden.map { $0.title })
        for (idx, info) in hidden.enumerated() {
            let it = NSMenuItem(title: info.title, action: #selector(didPickHiddenItem(_:)), keyEquivalent: "")
            it.tag = idx
            it.target = self
            it.isEnabled = true
            // 尺寸已在缩略图管线里按 Self.iconPointSize 定好,这里**不能再改 size** ——
            // 同一张 NSImage 会被菜单反复复用,每次压回会让放大设置失效
            let row = MenuRowView(title: info.title, icon: info.image)
            row.frame.size.width = rowWidth
            it.view = row
            menu.addItem(it)
        }
        // 本次没用上缩略图的项,趁菜单开着在后台补齐,下次展开就有图
        warmThumbCache()
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        installScreenshotHotKeyMonitor(menu: menu)
    }

    // 备注(2026-09-11 用独立菜单程序逐行抓帧实测):`menu.appearance = .darkAqua` 在这条路径上
    // 是**生效**的(整个菜单会变深),早前记为「不生效」是测量方式的问题。
    // 这里仍然不改菜单外观:系统默认外观符合用户预期,而图标可见性已经由
    // 「单色图标标成模板图」从根上解决(见 `fitted`),不需要再靠改底色去迁就图标。

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        removeScreenshotHotKeyMonitor()
    }

    /// 下拉期间监听截图快捷键:按到即收回下拉并进入截屏
    private func installScreenshotHotKeyMonitor(menu: NSMenu) {
        removeScreenshotHotKeyMonitor()
        let shotCfg = AppConfig.load().screenshot
        let shotCode = UInt16(shotCfg.hotKeyCode)
        let shotMods = shotCfg.hotKeyModifiers
        menuKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var mods = 0
            if flags.contains(.command) { mods |= 256 }   // cmdKey
            if flags.contains(.option)  { mods |= 2048 }  // optionKey
            if flags.contains(.control) { mods |= 4096 }  // controlKey
            if flags.contains(.shift)   { mods |= 512 }   // shiftKey
            if event.keyCode == shotCode && mods == shotMods {
                menu.cancelTracking()
                self?.removeScreenshotHotKeyMonitor()
                DispatchQueue.main.async { ScreenshotSession.launch() }
                return nil
            }
            return event
        }
    }

    private func removeScreenshotHotKeyMonitor() {
        if let m = menuKeyMonitor { NSEvent.removeMonitor(m); menuKeyMonitor = nil }
    }

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

    // MARK: - 状态项缩略图(绕开已废弃的 CGWindowListCreateImage)

    /// 拿不到缩略图/应用图标时的占位图。用户要求菜单里不许出现 `?` 行：
    /// 图标实在没有就用纯透明图顶位（文字兜底见 `MenuLabel.fallbackTitle`），
    /// 条目照样保留可点击 —— 点击靠 windowNumber、与图标无关。
    private static func unknownIcon() -> NSImage? {
        let size = NSSize(width: iconPointSize, height: iconPointSize)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        img.unlockFocus()
        return img
    }

    /// 菜单项图标的显示尺寸(pt)。
    ///
    /// 主路径是应用自带图标(矢量、自带留白),尺寸与 `MenuRowLayout.iconSide` 一致 ——
    /// 菜单行是自绘的,行高不受系统菜单行限制,所以这里可以给到 26pt 的大图标观感。
    private static let iconPointSize: CGFloat = MenuRowLayout.iconSide

    /// 菜单项图标的像素画布(52px = 26pt @2x)
    private static var thumbCanvasPixels: Int { Int(iconPointSize * 2) }

    /// 用系统 `screencapture` 按窗口号抓图,裁掉透明边距、等比放进 16pt 画布。
    /// **必须在后台线程调用**(内部 fork 子进程 + 位图运算)。
    private static func captureThumb(_ id: CGWindowID) -> NSImage? {
        let path = NSTemporaryDirectory() + "flowbox_thumb_\(id)_\(UUID().uuidString).png"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(id), path]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let img = NSImage(contentsOfFile: path),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cg = rep.cgImage else { return nil }
        // 抓到的是一整个状态项窗口(本机实测 76x66 @2x),图标只占中间一小块(约 40x32),
        // 四周全是透明边 —— 不裁边直接缩到 16pt,图标会被压成一小坨糊掉。裁完再等比放进画布。
        let cropped = IconTrim.trimmed(cg)
        return fitted(cropped, canvasPixels: thumbCanvasPixels)
    }

    /// 等比缩放进 canvasPixels × canvasPixels 的透明画布并居中。
    /// 用 CGContext 而不是 `NSImage.lockFocus` —— 后者在后台线程会踩到共享绘图上下文。
    private static func fitted(_ cg: CGImage, canvasPixels: Int) -> NSImage? {
        guard canvasPixels > 0,
              let ctx = CGContext(data: nil, width: canvasPixels, height: canvasPixels,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        let scale = min(CGFloat(canvasPixels) / CGFloat(cg.width),
                        CGFloat(canvasPixels) / CGFloat(cg.height))
        let w = CGFloat(cg.width) * scale
        let h = CGFloat(cg.height) * scale
        ctx.draw(cg, in: CGRect(x: (CGFloat(canvasPixels) - w) / 2,
                                y: (CGFloat(canvasPixels) - h) / 2,
                                width: w, height: h))
        guard let out = ctx.makeImage() else { return nil }
        let image = NSImage(cgImage: out, size: NSSize(width: canvasPixels / 2, height: canvasPixels / 2))
        // 状态项缩略图是系统按**菜单栏**外观渲染的单色图形(深色壁纸→近白),而菜单底色另有一套
        // 规则(本机:浅色菜单)。白图标落浅色底本来就发虚,鼠标悬停时 macOS 26 会画一枚**浅色胶囊**,
        // 白上白直接看不见(用户报的「图标和背景都是白」)。
        // 标成模板图,AppKit 就会用当前菜单文字色重绘 —— 普通态/悬停态、浅色/深色菜单四种组合都可见。
        // 彩色图标保持原样,免得被压成单色剪影。
        image.isTemplate = IconContrast.isMonochrome(out)
        return image
    }

    /// 后台预热缩略图缓存:只抓还没有的窗口号,并丢弃已不在列表里的旧项。可在主线程直接调用。
    private func warmThumbCache() {
        let ids = hiddenCache.map { $0.windowNumber }
        guard !ids.isEmpty else { thumbCache.removeAll(); return }
        let known = Set(thumbCache.keys)
        let missing = ids.filter { !known.contains($0) }
        guard !missing.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var fetched: [CGWindowID: NSImage] = [:]
            for id in missing {
                if let img = Self.captureThumb(id) { fetched[id] = img }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                for (k, v) in fetched { self.thumbCache[k] = v }
                let live = Set(ids)
                self.thumbCache = self.thumbCache.filter { live.contains($0.key) }
                FlowLog.menuBar.info("缩略图缓存 \(fetched.count)/\(missing.count) 抓到,共 \(self.thumbCache.count) 项")
            }
        }
    }

    // MARK: - 主屏锚定

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// 「被挤判定屏」—— 菜单栏收纳的语义锚点,与用户在哪块屏上工作无关。
    ///
    /// 优先选**带刘海的屏**(`auxiliaryTopLeft/RightArea` 非空):只有刘海/安全区会把状态项
    /// 挤出可视区,这正是要收纳的对象;全部屏都无刘海时退化用 AppKit 主屏(`screens.first`,
    /// 文档保证对应带菜单栏的 primary screen)。
    /// ⚠️ 不能用 `CGMainDisplayID()`:实测它跟随键盘焦点所在屏 —— 用户在双屏间工作时
    /// 每轮采样都会跳变(2026-09-11 实测 5 分钟 28 次),外接屏镜像会被整批当成主屏窗口。
    private static func mainScreen() -> NSScreen? {
        let notched = NSScreen.screens.first { s in
            if let r = s.auxiliaryTopRightArea, !r.isNull,
               let l = s.auxiliaryTopLeftArea, !l.isNull { return true }
            return false
        }
        return notched ?? NSScreen.screens.first
    }

    /// 主屏菜单栏「可见状态项」的 X 区间(CG 坐标,原点左上但 X 与 Cocoa 同单位同向,已定标)。
    ///
    /// 刘海机型上菜单栏被刘海切成左右两段,中间那段是**物理不可见区** ——
    /// 被挤到那里的图标正是我们要收进下拉的「隐藏项」。所以可见区是两段而不是一整条。
    /// 拿不到刘海信息(无刘海屏)时退化成整条主屏宽度。
    private static func visibleStatusXRanges() -> [ClosedRange<CGFloat>] {
        guard let main = mainScreen() else { return [] }
        let lo = main.frame.minX, hi = main.frame.maxX
        if let right = main.auxiliaryTopRightArea, !right.isNull,
           let left = main.auxiliaryTopLeftArea, !left.isNull {
            return [lo...left.maxX, right.minX...hi]
        }
        return [lo...hi]
    }

    /// 非主屏(外接显示器)的 X 范围。
    ///
    /// macOS 会为同一批状态项在**每块屏**各渲染一份独立窗口(x 落在该屏范围内)。这些是镜像副本,
    /// 不是"被挤掉的隐藏项" —— 把它们也算进来,下拉里就会出现双份同名条目(用户报的「两个 QQ」)。
    private static func secondaryScreenXRanges() -> [ClosedRange<CGFloat>] {
        guard let mainID = mainScreen().flatMap(displayID(of:)) else { return [] }
        return NSScreen.screens
            .filter { displayID(of: $0) != mainID }
            .map { $0.frame.minX...$0.frame.maxX }
    }

    private func buildHiddenList() -> [HiddenInfo] {
        // 主屏锚定失败 = 屏幕列表瞬时异常(内置屏短暂离列表等)。此时任何几何判定都不可信:
        // 空可见区会把全部窗口(含外接屏镜像)判成「隐藏」列进下拉,造成顶栏+下拉同名重复。
        // 沿用上轮快照过渡,下一轮列表恢复后自然刷新。
        guard Self.mainScreen() != nil else {
            FlowLog.menuBar.info("主屏锚定失败(屏幕列表异常),沿用上轮快照 \(self.hiddenCache.count) 项")
            return hiddenCache
        }
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownNumbers: Set<Int> = [
            arrowItem?.button?.window?.windowNumber,
            mainStatusItem?.button?.window?.windowNumber,
        ].compactMap { $0 }.reduce(into: Set<Int>()) { $0.insert($1) }

        // CG 的 `kCGWindowIsOnscreen` 语义 ≠「在顶栏可见」:被挤掉的窗口仍报 ON,
        // 所以它不能用来区分可见/隐藏(2026-09-11 实测:几乎所有 layer-25 窗口都报 ON)。
        // 改用坐标判定:① 落在副屏范围内的窗口不进下拉(那是同一项的镜像副本);
        // ② 主屏按可见区(刘海左右两段)判定谁被挤掉了。
        //
        // 但副屏那批**不能丢** —— autosaveName(窗口名)常常只落在其中一份上,它是主屏匿名项
        // 唯一的可靠身份来源,收进 `clones` 备用(见下方 crossScreenName)。
        let visibleRanges = Self.visibleStatusXRanges()
        let secondaryRanges = Self.secondaryScreenXRanges()
        struct Win { let num: Int; let x: CGFloat; let width: CGFloat; let winName: String; let isVisible: Bool }
        var wins: [Win] = []
        var clones: [Win] = []
        for w in list {
            guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "控制中心",
                  let layer = w[kCGWindowLayer as String] as? Int, layer == 25,
                  let num = w[kCGWindowNumber as String] as? Int else { continue }
            if ownNumbers.contains(num) { continue }
            let b = w[kCGWindowBounds as String] as? [String: Any]
            let x = (b?["X"] as? CGFloat) ?? (b?["X"] as? Double).map { CGFloat($0) } ?? 0
            let wd = (b?["Width"] as? CGFloat) ?? (b?["Width"] as? Double).map { CGFloat($0) } ?? 0
            let winName = w[kCGWindowName as String] as? String ?? ""
            // FlowBox 的三个窗口用名字过滤更稳(主图标的 windowNumber 不在 hider 里)
            if winName.hasPrefix("FlowBox") { continue }
            if Self.ownBundleIDs.contains(winName.lowercased()) { continue }
            if secondaryRanges.contains(where: { $0.contains(x) }) {
                clones.append(Win(num: num, x: x, width: wd, winName: winName, isVisible: false))
                continue
            }
            wins.append(Win(num: num, x: x, width: wd, winName: winName,
                            isVisible: visibleRanges.contains(where: { $0.contains(x) })))
        }
        // 固定成菜单栏的视觉顺序(自右向左),不要直接吃 CGWindowList 的原始顺序 ——
        // 否则菜单条目顺序每次打开都可能不一样
        wins.sort { $0.x > $1.x }

        // 防瞬变兜底:显示链路重协商的瞬间,main display(连带 CGMainDisplayID 与 NSScreen 顺序)
        // 会短暂翻到外接屏再翻回。单轮采样恰好落在窗口内时,主屏锚定仍会拿到外接屏,
        // 整列表变成「镜像当真身」。这种翻转的指纹是主屏窗口号集合与上轮**零交集** ——
        // 自然状态不可能(开关一个图标只增删一两个窗口),据此识别并沿用上轮结果过渡。
        let curMainIDs = Set(wins.map { $0.num })
        if !lastMainWinIDs.isEmpty, curMainIDs.isDisjoint(with: lastMainWinIDs) {
            FlowLog.menuBar.info("主屏窗口集与上轮零交集(显示拓扑瞬变),沿用上轮 \(self.hiddenCache.count) 项")
            return hiddenCache
        }
        lastMainWinIDs = curMainIDs

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
        // 具名条目按窗口名直接匹配(如 WiFi/Battery/BentoBox),不参与通用排序。
        // 这些窗口名与位置键是**精确**对应的,所以它们还能反过来当锚点用(见下方校验)。
        var nameToEntry: [String: PosEntry] = [:]
        for e in allEntries where e.key != "NSStatusItem Preferred Position Item-0" {
            let short = e.key.replacingOccurrences(of: "NSStatusItem Preferred Position ", with: "")
            nameToEntry[short] = e
        }

        // 各屏窗口实测到的「应用 → 窗口宽度」表,给位置键对齐当硬约束用(见 widthsConsistent)。
        // 只能从「带身份名的窗口」上学:匿名项自己就是在等配对的那个。
        var knownWidths: [String: Double] = [:]
        for w in wins + clones where StatusItemPairing.isIdentifiableName(w.winName) {
            let d = w.winName.lowercased()
            if knownWidths[d] == nil { knownWidths[d] = Double(w.width) }
        }

        // 跨屏副本命名(**优先于位置键**):macOS 给同一批状态项在每块屏各渲染一份窗口,
        // 而 autosaveName 常常只落在其中一份上 —— 本机实测主屏 7 个匿名 `Item-0`,
        // 外接屏同 7 个却带着 bundle id。同一项在两侧的宽度必然相同,所以用宽度做硬约束对齐,
        // 比位置键(靠 position 单调反推)可靠得多。数量/宽度对不上就整批放弃。
        let recipientWins = wins.filter { !StatusItemPairing.isIdentifiableName($0.winName) }
        let donorWins = clones.filter { StatusItemPairing.isIdentifiableName($0.winName) }
        let cloneName = StatusItemPairing.crossScreenNames(
            recipients: recipientWins.map { StatusWindow(number: $0.num, x: Double($0.x), width: Double($0.width), name: $0.winName) },
            donors: donorWins.map { StatusWindow(number: $0.num, x: Double($0.x), width: Double($0.width), name: $0.winName) })
        if cloneName.isEmpty {
            FlowLog.menuBar.info("跨屏副本命名未启用(匿名\(recipientWins.count)/具名副本\(donorWins.count))")
        } else {
            let dump = cloneName.sorted { $0.key < $1.key }.map { "\($0.key)→\($0.value)" }.joined(separator: ", ")
            FlowLog.menuBar.info("跨屏副本命名 \(cloneName.count) 项:\(dump, privacy: .public)")
        }

        var numToGeneric: [Int: PosEntry] = [:]
        // 位置键 ↔ 窗口 的配对:两列都按「菜单栏从左到右」排序后一一对齐。
        //
        // 只有被 ⌘ 拖动过的图标才会写位置键(没拖过的没有键),退出应用的键又不会自己消失,
        // 所以两列长度经常不相等(实测本机 7 窗口 / 16 键)。位置值可比:**position 越小越靠右**,
        // 与窗口 x 严格反向单调,所以对齐后可用具名系统项(WiFi/Battery/BentoBox 的 x 与 position 都已知)
        // 当锚点校验整条阶梯。
        //
        // 【宁缺毋滥】只有两列**数量完全相等**时才配对。残留键混在中间时,用 min() 截断对齐会让整批
        // 错位一格 —— 而错位后的阶梯**依然单调**,单调校验根本发现不了(本机实测:7 键 7 窗那种
        // "长度相等"的巧合下,错位一格仍判"通过",于是把 QQ 的名字安到了别人头上)。
        // 再加一道宽度自检兜底,任一条不过就整批放弃:名字宁可不显示(退回窗口号),也不能张冠李戴。
        if !genericWins.isEmpty, genericWins.count == genericEntries.count {
            var candidate: [Int: PosEntry] = [:]
            for i in 0..<genericWins.count { candidate[genericWins[i].num] = genericEntries[i] }

            var ladder: [(x: CGFloat, pos: Double)] = genericWins.compactMap { w in
                candidate[w.num].map { (w.x, $0.value) }
            }
            for w in wins where StatusItemPairing.isIdentifiableName(w.winName) {
                if let e = nameToEntry[w.winName] { ladder.append((w.x, e.value)) }
            }
            ladder.sort { $0.x < $1.x }
            var monotonic = ladder.count >= 2
            for i in 1..<max(1, ladder.count) where ladder[i].pos >= ladder[i - 1].pos {
                monotonic = false
                break
            }
            let widthPairs: [(window: StatusWindow, bundleID: String)] = genericWins.compactMap { w in
                guard let e = candidate[w.num] else { return nil }
                return (StatusWindow(number: w.num, x: Double(w.x), width: Double(w.width), name: w.winName), e.domain)
            }
            let widthsOK = StatusItemPairing.widthsConsistent(widthPairs, knownWidths: knownWidths)
            if monotonic, widthsOK {
                numToGeneric = candidate
                FlowLog.menuBar.info("位置映射 \(candidate.count) 项,锚点 \(ladder.count) 级单调+宽度校验通过")
            } else {
                FlowLog.menuBar.info("位置映射校验未通过(单调=\(monotonic) 宽度=\(widthsOK),窗口\(genericWins.count)/键\(genericEntries.count)),降级为窗口号")
            }
        } else {
            FlowLog.menuBar.info("位置映射未启用(窗口\(genericWins.count)/键\(genericEntries.count) 数量不等,不猜)")
        }

        var out: [HiddenInfo] = []
        for w in wins {
            // 下拉只列真隐藏:已在顶栏可见的不再列入(根治"顶栏一个 QQ、下拉又一个 QQ")。
            // 可见性判不出(aux 为 nil)时保守保留,宁可重复也不丢条目。
            if w.isVisible { continue }
            var title: String
            var img: NSImage?
            // 窗口真实缩略图(后台预抓的缓存);拿不到时用透明占位顶位,但**条目一律保留** ——
            // 点击靠 windowNumber、与图标无关,绝不能因为"截不到图"就把条目丢掉(曾因此把菜单清空)。
            // 标题永远非空(MenuLabel.fallbackTitle):不许出现 `?` 行,包名/窗口名都可以显示。
            let shot = thumbCache[CGWindowID(w.num)]
            var resolvedBID: String? = cloneName[w.num]
            if let donor = cloneName[w.num] {
                // 跨屏副本给出的身份通常就是 autosaveName/bundle id。能**精确**反查到应用就用应用
                // 自己的名字(QQ / 微信 / WorkBuddy)与图标;反查不到(系统项 `WiFi` 等)原样用它 ——
                // 绝不做模糊匹配,免得被 /Applications 里名字相近的 App 串味。
                var appIcon: NSImage? = nil
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: donor) {
                    appIcon = NSWorkspace.shared.icon(forFile: url.path)
                    appIcon?.size = NSSize(width: Self.iconPointSize, height: Self.iconPointSize)
                }
                if StatusItemPairing.looksLikeBundleID(donor) {
                    let info = appDisplayInfo(for: donor)
                    title = info.title.isEmpty ? donor : info.title
                    img = info.icon ?? appIcon ?? shot ?? Self.unknownIcon()
                } else {
                    title = donor
                    img = appIcon ?? shot ?? Self.unknownIcon()
                }
            } else if w.winName == "Item-0" {
                if let e = numToGeneric[w.num] {
                    // 配对已通过单调+宽度校验:优先用应用**自己的图标与名称**(理由同上)
                    let info = appDisplayInfo(for: e.domain)
                    title = info.title
                    img = info.icon ?? shot ?? Self.unknownIcon()
                    if title.isEmpty { title = MenuLabel.fallbackTitle(winName: "", bundleID: e.domain, windowNumber: w.num) }
                    resolvedBID = e.domain
                } else if let cached = identityCache[CGWindowID(w.num)] {
                    // 副屏镜像重建期(重连/重协商)跨屏命名断供:主屏窗口号没变,沿用上次身份
                    title = cached.title
                    img = cached.bundleID.flatMap { appDisplayInfo(for: $0).icon } ?? shot ?? Self.unknownIcon()
                    resolvedBID = cached.bundleID
                } else {
                    // 校验没通过:不猜名字,只挂窗口真实缩略图,标题用窗口号兜底
                    title = MenuLabel.fallbackTitle(winName: "", bundleID: nil, windowNumber: w.num)
                    img = shot ?? Self.unknownIcon()
                }
            } else if w.winName.isEmpty {
                if let cached = identityCache[CGWindowID(w.num)] {
                    title = cached.title
                    img = cached.bundleID.flatMap { appDisplayInfo(for: $0).icon } ?? shot ?? Self.unknownIcon()
                    resolvedBID = cached.bundleID
                } else {
                    // 空名匿名窗口且无映射:标题用窗口号兜底,保留可点击
                    title = MenuLabel.fallbackTitle(winName: "", bundleID: nil, windowNumber: w.num)
                    img = shot ?? Self.unknownIcon()
                }
            } else {
                // 具名窗口(WiFi/Battery 等系统项,或自带 autosaveName 的第三方项)。
                // ① 窗口名是人话(中文)直接用;
                // ② 是**能精确反查到应用**的 bundle id → 用应用自己的名字与图标(比裸包名像人话);
                // ③ 其余(域名/autosaveName)原样显示 —— 用户要求:可以出现包名,不许出现空标题。
                let disp = MenuLabel.displayable(w.winName)
                if !disp.isEmpty {
                    title = disp
                    img = shot ?? Self.unknownIcon()
                } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: w.winName) {
                    let info = appDisplayInfo(for: w.winName)
                    title = info.title.isEmpty ? w.winName : info.title
                    img = info.icon ?? NSWorkspace.shared.icon(forFile: url.path)
                    img?.size = NSSize(width: Self.iconPointSize, height: Self.iconPointSize)
                } else {
                    title = MenuLabel.fallbackTitle(winName: w.winName, bundleID: nil, windowNumber: w.num)
                    img = shot ?? Self.unknownIcon()
                }
            }
            if title.hasPrefix("FlowBox") { continue }
            // 拿到真实身份的记入缓存(bundleID 非空 = cloneName/位置映射/缓存三来源之一),
            // 供副屏镜像重建期断供时沿用;裸窗口号兜底项(bundleID 为 nil)不记,免得污染缓存
            if let bid = resolvedBID { identityCache[CGWindowID(w.num)] = (title, bid) }
            out.append(HiddenInfo(windowNumber: CGWindowID(w.num), title: title, image: img, bundleID: resolvedBID))
            if out.count >= 16 { break }
        }
        // 清掉已不在主屏窗口集里的死键(窗口关闭/应用退出后窗口号不再复用,缓存有界)
        let liveIDs = Set(wins.map { CGWindowID($0.num) })
        identityCache = identityCache.filter { liveIDs.contains($0.key) }
        let dump = out.map { "\($0.title)/\($0.windowNumber)" }.joined(separator: ", ")
        FlowLog.menuBar.info("隐藏项 \(out.count) 个:\(dump, privacy: .public)")
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
            "com.tencent.xinwechat": "微信",
            "com.tencent.qq": "QQ",
            "com.alibaba.dingtalk": "钉钉",
            "com.tencent.wework": "企业微信",
            "cn.trae.app": "Trae",
            "io.github.clash-verge-rev.clash-verge-rev": "Clash Verge",
            "com.legendsec.vpnclientx": "奇安信VPN",
        ]
        if let pretty = prettyNames[lk] {
            var icon: NSImage? = nil
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                icon = NSWorkspace.shared.icon(forFile: url.path)
                icon?.size = NSSize(width: Self.iconPointSize, height: Self.iconPointSize)
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
                icon.size = NSSize(width: Self.iconPointSize, height: Self.iconPointSize)
                let _v=(t, icon); iconCache[lk]=_v; return _v
            } else if pp == nil {
                let _v0=(t, nil as NSImage?); iconCache[lk]=_v0; return _v0
            }
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let raw = FileManager.default.displayName(atPath: url.path)
            let title = raw.hasSuffix(".app") ? String(raw.dropLast(4)) : (raw.isEmpty ? (bundleID.components(separatedBy: ".").last ?? bundleID) : raw)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: Self.iconPointSize, height: Self.iconPointSize)
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
                icon.size = NSSize(width: Self.iconPointSize, height: Self.iconPointSize)
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
                // CG y 是从屏幕左上角算,需翻到 Cocoa 坐标再发 CGEvent。
                // 高度基准用主屏(CG 全局坐标 y=0 即主屏顶),不能用 screens.first ——
                // 顺序抖动时拿到外接屏高度,y 会整体偏移导致点错位置
                let screenH = Self.mainScreen()?.frame.height ?? NSScreen.screens.first?.frame.height ?? 900
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
