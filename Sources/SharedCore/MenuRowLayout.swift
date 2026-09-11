import CoreGraphics

/// 收纳菜单「一行」的几何常量与宽度规则。
///
/// 放在 SharedCore 是为了能被断言测试直接覆盖(不依赖 AppKit):菜单行是自绘的
/// (`MenuRowView`),行宽必须所有行统一 —— 菜单宽度由最宽的 item view 决定,
/// 各行算各的就会参差不齐。
public enum MenuRowLayout {

    // 尺寸按「大图标 + 应用名」的列表观感定(2026-09-11 用户指定的参考样式):
    // 图标 ≈ 行高的 0.65、文字 ≈ 图标高度的 0.6。原先是贴着系统菜单行的 22/18/13pt,
    // 在小尺寸下图标挤成一团、认不出是哪个应用。
    /// 行高
    public static let rowHeight: CGFloat = 40
    /// 图标边长
    public static let iconSide: CGFloat = 26
    /// 图标左内边距
    public static let iconLeading: CGFloat = 16
    /// 图标与文字之间的间隙
    public static let titleGap: CGFloat = 10
    /// 文字右侧留白
    public static let trailingInset: CGFloat = 16

    /// 标题字号(点)
    public static let titleFontSize: CGFloat = 16

    /// 文字起点 x(同时是「前缀宽度」)
    public static var titleOriginX: CGFloat { iconLeading + iconSide + titleGap }

    public static let defaultMinimumWidth: CGFloat = 200
    public static let defaultMaximumWidth: CGFloat = 420

    /// 统一行宽:在「刚好放下前缀 + 最宽文字」和下限/上限之间取中。
    ///
    /// - Parameter widestTitle: 所有行里最宽那行文字的宽度(0 表示全是没有文字的纯图标行)
    public static func unifiedWidth(widestTitle: CGFloat,
                                    minimum: CGFloat = defaultMinimumWidth,
                                    maximum: CGFloat = defaultMaximumWidth) -> CGFloat {
        let needed = titleOriginX + max(0, widestTitle) + trailingInset
        return min(max(minimum, needed), maximum)
    }
}
