import AppKit
import SharedCore

/// 收纳菜单里的一行:整行自绘,选中时画「蓝色圆角底 + 白色图标 + 白色文字」。
///
/// 为什么不用系统默认高亮(2026-09-11 用独立菜单程序逐行抓帧实测):
/// 二级菜单挂在 `statusItem.menu` 上,弹出时宿主 app 处于**未激活**状态,系统画的选中态是
/// 一枚**浅紫灰胶囊**(此时 `NSColor.selectedContentBackgroundColor` 解析出来的就是那个浅色),
/// 而这是一次性整行绘制,没有公开 API 能只换它的填充色。用户要的是蓝底白字,只能改成
/// `NSMenuItem.view` 自绘。
///
/// 实测确认过三件事:
/// 1. 自绘底色 + 白色图标/文字可见。选中色取 `NSColor.controlAccentColor` —— 它在未激活的
///    菜单里仍解析成系统蓝 `#007AFF`,并跟随用户的强调色设置。
/// 2. `enclosingMenuItem` 在 view 内部可用,`mouseUp` 里 `NSApp.sendAction` 能正常触发菜单项动作。
///    **自定义 view 的 item,系统不会自动派发动作**,必须自己来。
/// 3. 鼠标悬停用 `NSTrackingArea`;键盘上下键的高亮靠轻量轮询 `enclosingMenuItem.isHighlighted`
///    —— 该属性不是 KVO 兼容的,不能 observe。
final class MenuRowView: NSView {

    // MARK: - 几何(常量与宽度规则见 SharedCore/MenuRowLayout)

    static let rowHeight = MenuRowLayout.rowHeight
    static let iconSide = MenuRowLayout.iconSide
    static let iconLeading = MenuRowLayout.iconLeading
    static let titleGap = MenuRowLayout.titleGap
    static let trailingInset = MenuRowLayout.trailingInset
    static var titleOriginX: CGFloat { MenuRowLayout.titleOriginX }

    /// 选中底比行本身内缩一点做出胶囊感(比系统那枚浅色胶囊略大,确保完全盖住它)
    private static let highlightInsetX: CGFloat = 6
    private static let highlightInsetY: CGFloat = 1
    private static let highlightRadius: CGFloat = 8

    static let titleFont = NSFont.systemFont(ofSize: MenuRowLayout.titleFontSize)

    /// 统一行宽:菜单宽度由最宽的 item view 决定,各行给同一宽度才不会参差不齐。
    static func unifiedWidth(forTitles titles: [String],
                             minimum: CGFloat = MenuRowLayout.defaultMinimumWidth) -> CGFloat {
        var widest: CGFloat = 0
        for title in titles where !title.isEmpty {
            widest = max(widest, (title as NSString).size(withAttributes: [.font: titleFont]).width)
        }
        return MenuRowLayout.unifiedWidth(widestTitle: widest, minimum: minimum)
    }

    // MARK: - 内容

    var title: String {
        didSet { needsDisplay = true }
    }
    var isEnabled: Bool

    /// 图标交给 `NSImageView.contentTintColor` 着色 —— 模板图(单色状态项缩略图)会自动跟随
    /// 菜单明暗,选中时转白;彩色应用图标不受 tint 影响,保持原色(不会被压成剪影)。
    private let iconView = NSImageView()

    // MARK: - 状态

    private var hovered = false { didSet { syncHighlight() } }
    private var systemHighlighted = false { didSet { syncHighlight() } }
    private var isHot = false {
        didSet {
            guard isHot != oldValue else { return }
            applyHighlightAppearance()
        }
    }
    private var trackingArea: NSTrackingArea?
    private var syncTimer: Timer?

    init(title: String, icon: NSImage?, isEnabled: Bool = true) {
        self.title = title
        self.isEnabled = isEnabled
        super.init(frame: NSRect(x: 0, y: 0, width: 170, height: Self.rowHeight))
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.contentTintColor = .labelColor
        addSubview(iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: - 布局与绘制

    override func layout() {
        super.layout()
        iconView.frame = NSRect(x: Self.iconLeading,
                                y: (bounds.height - Self.iconSide) / 2,
                                width: Self.iconSide,
                                height: Self.iconSide)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHot {
            NSColor.controlAccentColor.setFill()
            let capsule = bounds.insetBy(dx: Self.highlightInsetX, dy: Self.highlightInsetY)
            NSBezierPath(roundedRect: capsule,
                         xRadius: Self.highlightRadius,
                         yRadius: Self.highlightRadius).fill()
        }

        guard !title.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.titleFont,
            .foregroundColor: isHot ? NSColor.white
                                    : (isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor),
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: Self.titleOriginX, y: (bounds.height - size.height) / 2),
                  withAttributes: attributes)
    }

    private func applyHighlightAppearance() {
        iconView.contentTintColor = isHot ? .white : .labelColor
        needsDisplay = true
    }

    // MARK: - 交互

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, let item = enclosingMenuItem, let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
        item.menu?.cancelTracking()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncTimer?.invalidate()
        syncTimer = nil
        guard window != nil else {
            systemHighlighted = false
            return
        }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.systemHighlighted = self.enclosingMenuItem?.isHighlighted ?? false
        }
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        syncTimer = timer
    }

    private func syncHighlight() {
        let next = hovered || systemHighlighted
        if next != isHot { isHot = next }
    }
}
