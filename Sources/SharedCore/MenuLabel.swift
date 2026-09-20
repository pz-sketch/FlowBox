import Foundation

/// 菜单栏收纳条目的文字取舍。
///
/// 状态项的窗口名常常是**机器标识**而不是人话：`omlx.metric.live`（服务域名）、
/// `BentoBox-0`、`com.xxx.yyy`（autosaveName 直接写成 bundle id）……
/// 中文系统里真正可读的名字一定含 CJK 字符（如「聚焦」「电池」），所以优先保留这类；
/// 其余走 `fallbackTitle` 原样显示（用户允许显示包名/窗口名）—— 菜单里不许出现空标题行。
///
/// 不依赖 AppKit，便于单测覆盖。
public enum MenuLabel {

    /// 返回可展示的标题；若窗口名不像人话则返回空串（调用方再走 `fallbackTitle` 兜底）。
    public static func displayable(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "" }
        return containsCJK(t) ? t : ""
    }

    /// 标题最终兜底：保证永远非空。
    /// - 窗口名非空（包名/autosaveName/具名）→ 原样显示；
    /// - `Item-N` 这类匿名名、无映射时 → 显示带窗口号的标签，避免多行重名无法区分；
    /// - 窗口名也为空 → 用 bundleID；再没有 → 带窗口号的标签。
    public static func fallbackTitle(winName: String, bundleID: String?, windowNumber: Int) -> String {
        let t = winName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty {
            if t == "Item-0" || (t.hasPrefix("Item-") && Int(t.dropFirst(5)) != nil) {
                return anonymousLabel(windowNumber)
            }
            return t
        }
        if let b = bundleID, !b.isEmpty { return b }
        return anonymousLabel(windowNumber)
    }

    /// 匿名状态项显示名的前缀（双语——运行时指纹判断与测试都必须覆盖两种语言）
    public static let anonymousPrefixes = ["菜单栏图标", "Menu bar icon"]

    /// 匿名状态项的显示名（双语，避免英文系统下兜底行仍是中文）
    private static func anonymousLabel(_ windowNumber: Int) -> String {
        L10n.tr(anonymousPrefixes[0], anonymousPrefixes[1]) + " \(windowNumber)"
    }

    /// 标题是否为匿名兜底行（「菜单栏图标 N」/「Menu bar icon N」,末尾纯数字）。
    /// 运行时指纹判断（如收纳辨认的触发条件）应使用本函数,不可对某一语言写死前缀。
    public static func isAnonymousFallback(_ title: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in anonymousPrefixes where t.hasPrefix(prefix) {
            let rest = t.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return !rest.isEmpty && rest.allSatisfy { $0.isNumber }
        }
        return false
    }

    /// 是否含 CJK 字符（汉字本体、扩展 A、兼容区、中文标点、全角块）。
    public static func containsCJK(_ s: String) -> Bool {
        for u in s.unicodeScalars {
            switch u.value {
            case 0x3400...0x4DBF,   // CJK 扩展 A
                 0x4E00...0x9FFF,   // CJK 基本区
                 0xF900...0xFAFF,   // CJK 兼容表意文字
                 0x3000...0x303F,   // CJK 符号与标点
                 0xFF00...0xFFEF:   // 全角及半角形式
                return true
            default:
                continue
            }
        }
        return false
    }
}
