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
        /// 滑杆与数值输入框（设置页所有参数行共用同一宽度，避免各行参差）
        static let sliderWidth: CGFloat = 150
        static let numberFieldWidth: CGFloat = 64
        /// 参数行左侧标签列宽度（步进器/滑杆因此能纵向对齐）
        static let labelColumnWidth: CGFloat = 210

        /// 设置窗口
        static let windowWidth: CGFloat = 680
        /// 默认高度取「让大多数 Tab 免滚动」的值：内容更长的 Tab 在窗口内滚动，窗口本身不再随 Tab 变形
        static let windowHeight: CGFloat = 660
        static let minimumWindowWidth: CGFloat = 520
        static let minimumWindowHeight: CGFloat = 420
        /// 设置窗口内容区左右内边距，也是窗口顶部留白（透明标题栏下）
        static let windowPadding: CGFloat = 24
        static let windowTopInset: CGFloat = 18
        /// 透明标题栏窗口里，内容首行需要避开的红黄绿按钮区域高度
        static let titlebarClearance: CGFloat = 34

        /// 卡片内边距
        static let cardPadding: CGFloat = 16

        /// HUD（截图覆盖层 / 录屏悬浮条）：这类浮层压在用户画面上，永远走深色高对比方案
        static let hudRadius: CGFloat = 10
        static let hudRadiusS: CGFloat = 6
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
        static var cardBorder: NSColor { .separatorColor.withAlphaComponent(0.65) }
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

        /// HUD 色板：压在用户屏幕画面上，不跟随系统深浅色，固定高对比取值
        enum HUD {
            /// 悬浮条/底板
            static let panel = NSColor(white: 0.14, alpha: 0.92)
            static let panelBorder = NSColor.white.withAlphaComponent(0.12)
            static let separator = NSColor.white.withAlphaComponent(0.14)

            /// 压暗整屏（截图选区之外、倒计时遮罩）
            static let scrim = NSColor.black.withAlphaComponent(0.35)
            static let scrimStrong = NSColor.black.withAlphaComponent(0.72)
            /// 自动消失的结果提示条
            static let toastFill = NSColor.black.withAlphaComponent(0.76)

            /// 亮色工具条（截图标注重叠层）
            static let toolbarFill = NSColor.white.withAlphaComponent(0.94)
            static let toolbarBorderOuter = NSColor.black.withAlphaComponent(0.10)
            static let toolbarBorderInner = NSColor.white.withAlphaComponent(0.65)
            static let groupFill = NSColor.black.withAlphaComponent(0.06)
            static let groupBorder = NSColor.black.withAlphaComponent(0.07)
            static let groupDivider = NSColor.black.withAlphaComponent(0.10)
            static let confirmFill = NSColor.systemGreen.withAlphaComponent(0.95)
            static let iconActive = NSColor.controlAccentColor
            static let iconActiveFill = NSColor.controlAccentColor.withAlphaComponent(0.15)
            static let iconActiveBorder = NSColor.controlAccentColor.withAlphaComponent(0.22)
            static let labelFill = NSColor.black.withAlphaComponent(0.6)
            static let hintFill = NSColor.black.withAlphaComponent(0.55)

            /// 文字
            static let text = NSColor.white
            static let textDim = NSColor.white.withAlphaComponent(0.9)
            static let textOnLight = NSColor.black.withAlphaComponent(0.88)
            static let textOnLightDim = NSColor.black.withAlphaComponent(0.32)

            /// 选区与手柄
            static let selectionStroke = NSColor.white
            static let selectionHandleShadow = NSColor.black.withAlphaComponent(0.45)

            /// 阴影
            static let shadow = NSColor.black.withAlphaComponent(0.22)
        }
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
        /// HUD 文本（截图覆盖层、录屏悬浮条）
        static func hudText(_ size: CGFloat = 12, weight: NSFont.Weight = .semibold) -> NSFont {
            .systemFont(ofSize: size, weight: weight)
        }
        /// HUD 数字/时间
        static func hudMono(_ size: CGFloat = 11, weight: NSFont.Weight = .medium) -> NSFont {
            .monospacedDigitSystemFont(ofSize: size, weight: weight)
        }
    }

    // MARK: - 4. 底层工具

    /// 图层着色的通用实现
    ///
    /// `layer?.backgroundColor = color.cgColor` 会在赋值那一刻把动态色**解析死**，
    /// 之后切换深/浅色外观时图层仍是旧颜色（典型症状：深色下浅底白字看不清）。
    /// 因此所有用 layer 上色的视图都走这两个子类，在外观变化时重新解析动态色。
    class LayerBackedView: NSView {
        var fill: NSColor? { didSet { syncLayer() } }
        var stroke: NSColor? { didSet { syncLayer() } }
        var radius: CGFloat = 0 { didSet { syncLayer() } }
        var strokeWidth: CGFloat = 0 { didSet { syncLayer() } }
        /// 连续圆角（胶囊/卡片观感更顺）
        var continuousCorner: Bool = true

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            syncLayer()
        }

        /// 子类布局变化后调用（如自绘尺寸依赖 bounds）
        func syncLayer() {
            guard let layer else {
                wantsLayer = true
                syncLayer()
                return
            }
            layer.cornerRadius = radius
            if continuousCorner { layer.cornerCurve = .continuous }
            layer.borderWidth = strokeWidth
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.backgroundColor = fill?.cgColor
                layer.borderColor = stroke?.cgColor
            }
        }
    }

    /// 同上，用于按钮（主按钮/图标按钮的填充与描边）
    class LayerBackedButton: NSButton {
        var fill: NSColor? { didSet { syncLayer() } }
        var stroke: NSColor? { didSet { syncLayer() } }
        var radius: CGFloat = 0 { didSet { syncLayer() } }
        var strokeWidth: CGFloat = 0 { didSet { syncLayer() } }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            syncLayer()
        }

        func syncLayer() {
            wantsLayer = true
            guard let layer else { return }
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
            layer.borderWidth = strokeWidth
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.backgroundColor = fill?.cgColor
                layer.borderColor = stroke?.cgColor
            }
        }
    }

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

    /// 多行说明文字：宽度跟随容器（调用方配 `fillWidth`），不限行数以免截断文案
    static func hint(
        _ text: String,
        color: NSColor = Palette.textSecondary,
        font: NSFont = Text.caption()
    ) -> NSTextField {
        let l = label(text, font: font, color: color)
        l.lineBreakMode = .byWordWrapping
        l.maximumNumberOfLines = 0
        l.cell?.wraps = true
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    /// 参数行标签（滑杆 / 步进器 / 颜色选择器左侧）
    static func controlLabel(_ text: String, width: CGFloat? = nil) -> NSTextField {
        let l = label(text, font: Text.body(.medium), color: Palette.text)
        if let width {
            l.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        return l
    }

    /// 参数滑杆：统一小尺寸与宽度，避免各行宽窄不一
    static func slider(
        value: Double,
        min: Double,
        max: Double,
        target: AnyObject?,
        action: Selector,
        width: CGFloat = Metrics.sliderWidth
    ) -> NSSlider {
        let s = NSSlider(value: value, minValue: min, maxValue: max, target: target, action: action)
        s.controlSize = .small
        s.translatesAutoresizingMaskIntoConstraints = false
        s.widthAnchor.constraint(equalToConstant: width).isActive = true
        return s
    }

    /// 参数数值输入框
    static func numberField(
        _ value: Double,
        target: AnyObject?,
        action: Selector,
        width: CGFloat = Metrics.numberFieldWidth
    ) -> NSTextField {
        let f = NSTextField(string: String(format: "%.0f", value))
        f.target = target
        f.action = action
        f.alignment = .right
        f.font = Text.monoDigit(12)
        f.translatesAutoresizingMaskIntoConstraints = false
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        return f
    }

    /// 1px 分隔线（浅）
    static func hairline(_ color: NSColor = Palette.hairline) -> NSView {
        let v = LayerBackedView()
        v.continuousCorner = false
        v.translatesAutoresizingMaskIntoConstraints = false
        v.fill = color
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
        let box = LayerBackedView()
        box.fill = background ?? tint.withAlphaComponent(0.10)
        box.radius = Metrics.radiusM
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
        // 分组卡片不做投影：系统设置用的就是「浅底 + 细描边」，投影会让一排卡片显得零散
        box.layer?.masksToBounds = false
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

    /// 复选框 —— 统一字号与换行（仅用于非设置项场景；设置项的开关请用 `switchRow`）
    static func checkbox(_ title: String, target: AnyObject? = nil, action: Selector? = nil) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: target, action: action)
        b.font = Text.body()
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }

    /// 开关行：开关滑块 + 说明文字（对齐 macOS 系统设置的开关观感）
    ///
    /// 目标动作的 sender 是行本身；`state` / `isEnabled` / `identifier` / `tag` 都转发到内部滑块，
    /// 因此原来按 NSButton 写的开关逻辑只需把类型换成 `SwitchRow`。
    final class SwitchRow: NSView {

        let toggle = NSSwitch()
        private let titleLabel: NSTextField

        var target: AnyObject?
        var action: Selector?
        // tag / identifier 由 NSView 提供，无需重复声明

        var state: NSControl.StateValue {
            get { toggle.state }
            set { toggle.state = newValue }
        }

        /// 关闭时连同文字一起置灰，避免只看滑块状态
        var isEnabled: Bool = true {
            didSet {
                toggle.isEnabled = isEnabled
                titleLabel.textColor = isEnabled ? Palette.text : Palette.textTertiary
            }
        }

        init(title: String, target: AnyObject?, action: Selector?) {
            self.target = target
            self.action = action
            self.titleLabel = UIStyle.label(title, font: Text.body(), color: Palette.text)
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false

            toggle.translatesAutoresizingMaskIntoConstraints = false
            toggle.controlSize = .small
            toggle.target = self
            toggle.action = #selector(toggleChanged)
            toggle.setAccessibilityLabel(title)
            addSubview(toggle)
            addSubview(titleLabel)

            titleLabel.lineBreakMode = .byTruncatingTail
            NSLayoutConstraint.activate([
                toggle.leadingAnchor.constraint(equalTo: leadingAnchor),
                toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleLabel.leadingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: Metrics.sp10),
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
                titleLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: Metrics.sp2),
                titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -Metrics.sp2),
                heightAnchor.constraint(greaterThanOrEqualToConstant: Metrics.smallControlHeight),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not supported") }

        @objc private func toggleChanged() {
            guard let action else { return }
            NSApp.sendAction(action, to: target, from: self)
        }

        override func setAccessibilityLabel(_ accessibilityLabel: String?) {
            super.setAccessibilityLabel(accessibilityLabel)
            toggle.setAccessibilityLabel(accessibilityLabel)
        }
    }

    /// 开关行工厂（设置页里「勾选式」选项统一走这里）
    @discardableResult
    static func switchRow(_ title: String, target: AnyObject? = nil, action: Selector? = nil) -> SwitchRow {
        SwitchRow(title: title, target: target, action: action)
    }

    /// 主按钮：强调色填充
    @discardableResult
    static func primaryButton(_ title: String, symbol: String? = nil, target: AnyObject?, action: Selector?) -> NSButton {
        let b = LayerBackedButton()
        b.title = title
        b.target = target
        b.action = action
        b.bezelStyle = .inline
        b.isBordered = false
        b.fill = Palette.accent
        b.radius = Metrics.radiusM
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
        let b = LayerBackedButton()
        if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            img.isTemplate = true
            b.image = img
            b.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        } else {
            b.title = symbol
        }
        b.bezelStyle = .inline
        b.isBordered = false
        b.fill = Palette.control
        b.stroke = Palette.controlBorder
        b.strokeWidth = 1
        b.radius = Metrics.radiusS
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
    static func badge(_ text: String, tint: NSColor = Palette.textTertiary) -> NSView {
        pill(text, font: Text.mono(10), color: tint)
    }

    /// 胶囊标签（等宽小字，用于文件名/路径）
    static func pill(_ text: String, font: NSFont = Text.mono(10.5), color: NSColor = Palette.textSecondary) -> NSView {
        let container = LayerBackedView()
        container.fill = Palette.inset
        container.radius = Metrics.radiusS
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
        let v = LayerBackedView()
        v.fill = color
        v.radius = size / 2
        v.translatesAutoresizingMaskIntoConstraints = false
        v.widthAnchor.constraint(equalToConstant: size).isActive = true
        v.heightAnchor.constraint(equalToConstant: size).isActive = true
        return v
    }

    /// 状态药丸：软底 + 状态色文字
    static func statusPill(_ text: String, color: NSColor, background: NSColor) -> NSView {
        let container = LayerBackedView()
        container.fill = background
        container.radius = Metrics.radiusS
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

    /// 滚动容器的文档视图：需要顶左原点，否则内容从底部开始堆
    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    /// 创建一个设置 Tab：内容放进滚动容器
    ///
    /// 每个 Tab 的内容长度不同（人脸/录屏远长于菜单），若让内容直接决定高度，
    /// 切换 Tab 时窗口会跟着忽高忽低。这里统一在固定高度内滚动。
    @discardableResult
    static func makeTab(
        _ tabView: NSTabView,
        identifier: String,
        label: String,
        spacing: CGFloat = Metrics.sp18
    ) -> NSStackView {
        let item = NSTabViewItem(identifier: identifier)
        item.label = label

        let page = NSView()
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        let stack = vStack(spacing: spacing)
        document.addSubview(stack)

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .allowed
        page.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: page.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: page.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: page.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: page.bottomAnchor),

            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),

            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: Metrics.sp20),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -Metrics.sp20),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: Metrics.windowTopInset),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -Metrics.sp16),
        ])
        item.view = page
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
