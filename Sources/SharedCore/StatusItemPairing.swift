import Foundation

/// 状态项窗口的最小描述（纯值类型，不依赖 AppKit，便于单测覆盖）。
public struct StatusWindow: Equatable, Sendable {
    public let number: Int
    public let x: Double
    public let width: Double
    public let name: String

    public init(number: Int, x: Double, width: Double, name: String) {
        self.number = number
        self.x = x
        self.width = width
        self.name = name
    }
}

/// 状态项「窗口 ↔ 应用身份」的配对规则。
///
/// 菜单栏状态项的归属只能靠推断（窗口 owner 全是控制中心、第三方窗口名清一色 `Item-0`），
/// 所以这里的两条推断都必须**宁缺毋滥**：名字配错会让用户以为点错了 App。
public enum StatusItemPairing {

    /// 窗口名是否可直接当身份用：非空、且不是 `Item-0` / `Item-1` 这类匿名占位名。
    public static func isIdentifiableName(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return false }
        if t == "Item-0" { return false }
        if t.hasPrefix("Item-"), Int(t.dropFirst(5)) != nil { return false }
        return true
    }

    /// 跨屏副本命名：把 `recipients` 里**没有名字**的窗口，对齐到 `donors`（其它屏上**有名字**的同项副本）。
    ///
    /// 依据：macOS 会给同一批状态项在每块屏各渲染一份窗口，而 autosaveName（窗口名）常常只落在
    /// 其中一份上 —— 本机实测主屏 7 个匿名 `Item-0`，外接屏同 7 个却带着 bundle id。
    /// 同一项的窗口宽度是固有属性，所以拿**宽度**做硬约束，组内再按 x 顺序对齐。
    ///
    /// 放弃条件（返回空字典，一个都不猜）：
    /// - 两侧数量不等；
    /// - 两侧宽度集合不一致，或某个宽度分组内数量不等；
    /// - 某一对两侧都有名字却不同名（说明整批错位）。
    ///
    /// - Returns: `recipient.number` → 名字（通常是 bundle id）。
    public static func crossScreenNames(recipients: [StatusWindow], donors: [StatusWindow]) -> [Int: String] {
        guard !recipients.isEmpty, recipients.count == donors.count else { return [:] }

        // 宽度取整后再分组：浮点抖动不该让同一项落到两个组
        func grouped(_ ws: [StatusWindow]) -> [Int: [StatusWindow]] {
            Dictionary(grouping: ws) { Int($0.width.rounded()) }
        }
        let rGroups = grouped(recipients), dGroups = grouped(donors)
        guard Set(rGroups.keys) == Set(dGroups.keys) else { return [:] }

        var map: [Int: String] = [:]
        for (width, rs) in rGroups {
            guard let ds = dGroups[width], ds.count == rs.count else { return [:] }
            let rsx = rs.sorted { $0.x < $1.x }
            let dsx = ds.sorted { $0.x < $1.x }
            for (r, d) in zip(rsx, dsx) {
                // 两侧都有名字 → 必须同名，否则整批错位，宁可全部放弃
                if isIdentifiableName(r.name), isIdentifiableName(d.name),
                   r.name.caseInsensitiveCompare(d.name) != .orderedSame {
                    return [:]
                }
                if isIdentifiableName(d.name) { map[r.number] = d.name }
            }
        }
        return map
    }

    /// 名字是不是「可反查应用的 bundle id」形态（含点、无空格、纯 ASCII）。
    ///
    /// 只有这种名字才该拿去查应用名/图标。像 `WiFi`、`BentoBox-0` 这类系统项名若走模糊匹配，
    /// 会被 `/Applications` 里名字相近的 App 串味（`WiFi` 命中 `WiFiSpoof` 之类）。
    public static func looksLikeBundleID(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.contains("."), !t.contains(" ") else { return false }
        return t.unicodeScalars.allSatisfy { $0.isASCII }
    }

    /// 位置键对齐的宽度自检：键所属应用的**已知宽度**必须与窗口实测宽度相容。
    ///
    /// 位置键本身不带宽度，宽度只能从各屏窗口观测里学（`knownWidths`）—— 没观测到就跳过该项检查。
    /// 这条能挡住「残留键插在中间 → 整批错位一格但阶梯仍单调」的情况。
    public static func widthsConsistent(
        _ pairs: [(window: StatusWindow, bundleID: String)],
        knownWidths: [String: Double],
        tolerance: Double = 1
    ) -> Bool {
        var known: [String: Double] = [:]
        for (k, v) in knownWidths { known[k.lowercased()] = v }
        for p in pairs {
            guard let kw = known[p.bundleID.lowercased()] else { continue }
            if abs(kw - p.window.width) > tolerance { return false }
        }
        return true
    }
}
