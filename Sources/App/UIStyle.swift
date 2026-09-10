import AppKit

/// FlowBox 设计系统
///
/// 所有界面必须通过这里取值与创建控件，调用点不再出现硬编码字号、颜色、魔法数。
/// 分四层：
///  1. `Metrics`   — 间距 / 圆角 / 尺寸标度
///  2. `Palette`   — 语义色板（强调色跟随系统）
///  3. `Text`      — 排版标度
///  4. 组件工厂     — 卡片、区块头、提示、复选框、按钮、徽标、Tab 脚手架
enum UIStyle {

    // MARK: - 1. 度量

    /// 间距：4pt 基准。命名即数值，便于对齐检查。
    enum Metrics {
        static let sp2: CGFloat = 2
        static let sp4: CGFloat = 4
        static let sp6: CGFloat = 6
        static let sp8: CGFloat = 8
        static let sp10: CGFloat = 10
        static let sp12: CGFloat = 12
        static let sp14: CGFloat = 14
        static let sp16: CGFloat = 16
        static let sp18: CGFloat = 18
        static let sp20: CGFloat = 20
        static let sp24: CGFloat = 24
        static let sp28: CGFloat = 28
        static let sp32: CGFloat = 32

        /// 圆角
        static let radiusXS: CGFloat = 4
        static let radiusS: CGFloat = 6
        static let radiusM: CGFloat = 8
        static let radiusL: CGFloat = 12
        static let radiusXL: CGFloat = 16

        /// 常用尺寸
        static let controlHeight: CGFloat = 26
        static let smallControlHeight: CGFloat = 24
        static let iconButtonSize: CGFloat = 26
        static let chipSize: CGFloat = 28

        /// 设置窗口
        static let windowWidth: CGFloat = 680
        static let windowHeight: CGFloat = 580
        static let minimumWindowWidth: CGFloat = 520
        static let minimumWindowHeight: CGFloat = 420
        /// 设置窗口内容区左右内边距，也是窗口顶部留白（透明标题栏下）
        static let windowPadding: CGFloat = 24
        static let windowTopInset: CGFloat = 18

        /// 卡片内边距
        static let cardPadding: CGFloat = 16
    }

    // MARK: - 2. 色板（跟随系统强调色）

    enum Palette {
        /// 强调色 —— 跟随系统设置里的强调色，深/浅色自动适配
        static var accent: NSColor { .controlAccentColor }
        static var accentSoft: NSColor { accent.withAlphaComponent(0.14) }
        static var accentFaint: NSColor { accent.withAlphaComponent(0.08) }

        /// 三级表面：窗口 → 卡片 → 内嵌
        static var window: NSColor { .windowBackgroundColor }
        static var card: NSColor { .controlBackgroundColor.withAlphaComponent(0.6) }
        static var cardBorder: NSColor { .separatorColor.withAlphaComponent(0.5) }
        static var inset: NSColor { .separatorColor.withAlphaComponent(0.07) }
        static var control: NSColor { .controlBackgroundColor.withAlphaComponent(0.92) }
        static var controlBorder: NSColor { .separatorColor.withAlphaComponent(0.45) }
        static var hairline: NSColor { .separatorColor.withAlphaComponent(0.4) }

        /// 文本层级
        static var text: NSColor { .labelColor }
        static var textSecondary: NSColor { .secondaryLabelColor }
        static var textTertiary: NSColor { .tertiaryLabelColor }
        static var textQuaternary: NSColor { .quaternaryLabelColor }

        /// 状态色
        static var success: NSColor { .systemGreen }
        static var warning: NSColor { .systemOrange }
        static var danger: NSColor { .systemRed }
        static var successSoft: NSColor { .systemGreen.withAlphaComponent(0.13) }
        static var warningSoft: NSColor { .systemOrange.withAlphaComponent(0.13) }
        static var dangerSoft: NSColor { .systemRed.withAlphaComponent(0.13) }

        /// 中性强调（用于去隔离等非主功能）
        static var neutralTint: NSColor { .systemOrange }
        static var neutralSoft: NSColor { .systemOrange.withAlphaComponent(0.14) }
    }

    // MARK: - 3. 排版标度

    enum Text {
        /// 18pt semibold — 关于页大标题
        static func hero(_ weight: NSFont.Weight = .semibold) -> NSFont { .systemFont(ofSize: 18, weight: weight) }
        /// 15pt — 窗口主标题
        static func display(_ weight: NSFont.Weight = .semibold) -> NSFont { .systemFont(ofSize: 15, weight: weight) }
        /// 13pt — 区块标题
        static func title(_ weight: NSFont.Weight = .semibold) -> NSFont { .systemFont(ofSize: 13, weight: weight) }
        /// 12pt — 正文与控件标签
        static func body(_ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: 12, weight: weight) }
        /// 13pt — 长文本阅读（OCR 结果、模板内容等）
        static func reading(_ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: 13, weight: weight) }
        /// 11pt — 说明文字
        static func caption(_ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: 11, weight: weight) }
        /// 10.5pt — 次级说明
        static func micro(_ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: 10.5, weight: weight) }
        /// 10pt — 脚注/徽标
        static func footnote(_ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: 10, weight: weight) }
        /// 等宽 —— 路径、版本号、数值
        static func mono(_ size: CGFloat = 11, weight: NSFont.Weight = .regular) -> NSFont {
            .monospacedSystemFont(ofSize: size, weight: weight)
        }
        /// 等宽数字 —— 滑杆数值，避免抖动
        static func monoDigit(_ size: CGFloat = 11, weight: NSFont.Weight = .regular) -> NSFont {
            .monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
    }

    // MARK: - 4. 底层工具

    /// 垂直栈（默认左对齐）
    static func vStack(spacing: CGFloat = Metrics.sp12, alignment: NSLayoutConstraint.Attribute = .leading) -> NSStackView {
        let s = NSStackView()
        s.orientation = .vertical
        s.alignment = alignment
        s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    /// 水平栈（默认垂直居中）
    static func hStack(spacing: CGFloat = Metrics.sp8) -> NSStackView {
        let s = NSStackView()
        s.orientation = .horizontal
        s.alignment = .centerY
        s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }

    /// 弹性占位（吸收多余空间，用于把右侧内容推到边缘）
    static func spacer() -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.setContentHuggingPriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    /// 文本标签
    static func label(
        _ text: String,
        font: NSFont = Text.body(),
        color: NSColor = Palette.text
    ) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = font
        l.textColor = color
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }

    /// 多行说明文字（自动换行 + 行数上限）
    static func hint(
        _ text: String,
        color: NSColor = Palette.textSecondary,
        maxWidth: CGFloat = 480,
        lines: Int = 2,
        font: NSFont = Text.caption()
    ) -> NSTextField {
        let l = label(text, font: font, color: color)
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = lines
        l.preferredMaxLayoutWidth = maxWidth
        return l
    }

    /// 1px 分隔线（浅）
    static func hairline(_ color: NSColor = Palette.hairline) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.wantsLayer = true
        v.layer?.backgroundColor = color.cgColor
        v.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }

    /// 图标方块：圆角底 + SF Symbol
    static func iconChip(
        symbol: String,
        size: CGFloat = Metrics.chipSize,
        tint: NSColor = Palette.accent,
        background: NSColor? = nil,
        pointSize: CGFloat = 14
    ) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = (background ?? tint.withAlphaComponent(0.10)).cgColor
        box.layer?.cornerRadius = Metrics.radiusM
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: size).isActive = true
        box.heightAnchor.constraint(equalToConstant: size).isActive = true

        let iv = NSImageView()
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            iv.image = img
            iv.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            iv.contentTintColor = tint
        }
        iv.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(iv)
        NSLayoutConstraint.activate([
            iv.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            iv.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    // MARK: - 5. 卡片

    /// 卡片外观（作用于 NSBox）
    static func applyCardStyle(_ box: NSBox) {
        box.boxType = .custom
        box.borderWidth = 1
        box.borderColor = Palette.cardBorder
        box.cornerRadius = Metrics.radiusL
        box.fillColor = Palette.card
        box.titlePosition = .noTitle
        box.wantsLayer = true
        box.layer?.shadowColor = NSColor.black.cgColor
        box.layer?.shadowOpacity = 0.05
        box.layer?.shadowRadius = 10
        box.layer?.shadowOffset = NSSize(width: 0, height: 4)
        box.layer?.masksToBounds = false
    }

    /// 卡片外观（作用于任意 NSView）
    static func applySoftCard(_ view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.cornerRadius = Metrics.radiusL
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = Palette.cardBorder.cgColor
        layer.backgroundColor = Palette.card.cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowRadius = 10
        layer.shadowOffset = NSSize(width: 0, height: 4)
    }

    /// 把内容包进一张卡片，返回 NSBox
    static func card(_ inner: NSView, padding: CGFloat = Metrics.cardPadding) -> NSBox {
        let box = NSBox()
        applyCardStyle(box)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.contentViewMargins = .zero
        inner.translatesAutoresizingMaskIntoConstraints = false
        guard let content = box.contentView else { return box }
        content.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: padding),
            inner.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -padding),
            inner.topAnchor.constraint(equalTo: content.topAnchor, constant: padding),
            inner.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -padding),
        ])
        return box
    }

    /// 区块头：图标块 + 标题 + 副标题
    static func sectionHeader(
        title: String,
        subtitle: String,
        symbol: String? = nil,
        tint: NSColor = Palette.accent
    ) -> NSView {
        let row = hStack(spacing: Metrics.sp10)
        row.addArrangedSubview(iconChip(symbol: symbol ?? "sparkles", tint: tint))
        let stack = vStack(spacing: Metrics.sp2)
        stack.addArrangedSubview(label(title, font: Text.title(), color: Palette.text))
        let sub = label(subtitle, font: Text.caption(), color: Palette.textSecondary)
        sub.lineBreakMode = .byWordWrapping
        sub.maximumNumberOfLines = 2
        stack.addArrangedSubview(sub)
        row.addArrangedSubview(stack)
        return row
    }

    // MARK: - 6. 控件工厂

    /// 复选框 —— 统一字号与换行
    static func checkbox(_ title: String, target: AnyObject? = nil, action: Selector? = nil) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: target, action: action)
        b.font = Text.body()
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    /// 主按钮：强调色填充
    @discardableResult
    static func primaryButton(_ title: String, symbol: String? = nil, target: AnyObject?, action: Selector?) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.bezelStyle = .inline
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = Metrics.radiusM
        b.layer?.backgroundColor = Palette.accent.cgColor
        b.contentTintColor = .white
        b.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: Text.body(.medium),
            .foregroundColor: NSColor.white,
        ])
        if let symbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            b.image = img
            b.imagePosition = .imageLeading
        }
        b.controlSize = .small
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    /// 次按钮：描边 + 浅底
    @discardableResult
    static func secondaryButton(_ title: String, symbol: String? = nil, target: AnyObject?, action: Selector?) -> NSButton {
        let b = NSButton(title: title, target: target, action: action)
        b.bezelStyle = .rounded
        b.controlSize = .small
        b.wantsLayer = true
        b.layer?.cornerRadius = Metrics.radiusS
        b.layer?.borderWidth = 1
        b.layer?.borderColor = Palette.controlBorder.cgColor
        if let symbol, let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            b.image = img
            b.imagePosition = .imageLeading
        }
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    /// 图标按钮：正方形浅底 + 圆角
    @discardableResult
    static func iconButton(symbol: String, target: AnyObject?, action: Selector?, size: CGFloat = Metrics.iconButtonSize) -> NSButton {
        let b = NSButton()
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            img.isTemplate = true
            b.image = img
            b.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        } else {
            b.title = symbol
        }
        b.bezelStyle = .inline
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = Metrics.radiusS
        b.layer?.backgroundColor = Palette.control.cgColor
        b.layer?.borderWidth = 1
        b.layer?.borderColor = Palette.controlBorder.cgColor
        b.contentTintColor = Palette.textSecondary
        b.controlSize = .small
        b.target = target
        b.action = action
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: size).isActive = true
        b.heightAnchor.constraint(equalToConstant: size).isActive = true
        return b
    }

    /// 徽标（版本号等）
    static func badge(_ text: String, tint: NSColor = Palette.textTertiary) -> NSTextField {
        let l = label(text, font: Text.mono(10), color: tint)
        l.alignment = .center
        l.wantsLayer = true
        l.drawsBackground = false
        l.layer?.backgroundColor = Palette.inset.cgColor
        l.layer?.cornerRadius = Metrics.radiusS
        return l
    }

    /// 胶囊标签（等宽小字，用于文件名/路径）
    static func pill(_ text: String, font: NSFont = Text.mono(10.5), color: NSColor = Palette.textSecondary) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = Palette.inset.cgColor
        container.layer?.cornerRadius = Metrics.radiusS
        container.translatesAutoresizingMaskIntoConstraints = false
        let l = label(text, font: font, color: color)
        l.lineBreakMode = .byTruncatingMiddle
        l.setContentHuggingPriority(.defaultLow, for: .horizontal)
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        container.addSubview(l)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.sp6),
            l.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.sp6),
            l.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.sp2 + 1),
            l.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -(Metrics.sp2 + 1)),
        ])
        return container
    }

    /// 状态点（绿/黄/红）
    static func statusDot(_ color: NSColor, size: CGFloat = 6) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = color.cgColor
        v.layer?.cornerRadius = size / 2
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: size).isActive = true
        v.heightAnchor.constraint(equalToConstant: size).isActive = true
        return v
    }

    /// 状态药丸：软底 + 状态色文字
    static func statusPill(_ text: String, color: NSColor, background: NSColor) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = background.cgColor
        container.layer?.cornerRadius = Metrics.radiusS
        container.translatesAutoresizingMaskIntoConstraints = false
        let l = label(text, font: Text.caption(.medium), color: color)
        container.addSubview(l)
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Metrics.sp8),
            l.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Metrics.sp8),
            l.topAnchor.constraint(equalTo: container.topAnchor, constant: Metrics.sp2 + 1),
            l.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -(Metrics.sp2 + 1)),
        ])
        return container
    }

    /// 标签 + 数值（滑杆/步进器右侧的读数）
    static func valueLabel(_ text: String = "") -> NSTextField {
        let l = label(text, font: Text.monoDigit(11), color: Palette.textSecondary)
        l.alignment = .right
        return l
    }

    // MARK: - 7. 窗口 chrome

    /// 统一标题栏外观：透明标题栏 + 隐藏标题 + 副标题承载说明
    static func applyWindowChrome(_ window: NSWindow, subtitle: String? = nil) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        if #available(macOS 13.0, *) { window.toolbarStyle = .unifiedCompact }
        window.backgroundColor = Palette.window
        if let subtitle { window.subtitle = subtitle }
        window.isReleasedWhenClosed = false
        window.contentView?.wantsLayer = true
    }

    /// 在内容视图底部铺一层 HUD 材质（毛玻璃）
    @discardableResult
    static func attachHUDMaterial(to content: NSView) -> NSVisualEffectView {
        let bg = NSVisualEffectView()
        bg.material = .hudWindow
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bg, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            bg.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            bg.topAnchor.constraint(equalTo: content.topAnchor),
            bg.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        return bg
    }

    // MARK: - 8. Tab 脚手架

    /// 创建一个设置 Tab：标准内边距的垂直栈，调用方往里塞内容即可
    @discardableResult
    static func makeTab(
        _ tabView: NSTabView,
        identifier: String,
        label: String,
        spacing: CGFloat = Metrics.sp18
    ) -> NSStackView {
        let item = NSTabViewItem(identifier: identifier)
        item.label = label
        let view = NSView()
        let stack = vStack(spacing: spacing)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Metrics.sp20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Metrics.sp20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: Metrics.windowTopInset),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -Metrics.sp8),
        ])
        item.view = view
        tabView.addTabViewItem(item)
        return stack
    }

    /// 让子视图与父栈等宽（卡片、分隔线等纵向控件都需要）
    @discardableResult
    static func fillWidth(_ child: NSView, in parent: NSStackView, inset: CGFloat = 0) -> NSLayoutConstraint {
        let c = child.widthAnchor.constraint(equalTo: parent.widthAnchor, constant: -inset)
        c.isActive = true
        return c
    }
}
