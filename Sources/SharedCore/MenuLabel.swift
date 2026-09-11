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
                return "菜单栏图标 \(windowNumber)"
            }
            return t
        }
        if let b = bundleID, !b.isEmpty { return b }
        return "菜单栏图标 \(windowNumber)"
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
