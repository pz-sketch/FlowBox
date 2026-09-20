import Foundation

public enum AppLanguage: String, Codable, CaseIterable {
    case system = "system"
    case zh = "zh"
    case en = "en"
    public var displayName: String {
        switch self {
        case .system: return "Follow System / 跟随系统"
        case .zh: return "中文"
        case .en: return "English"
        }
    }
}

public enum L10n {
    public static var cachedLanguage: AppLanguage?
    private static var cacheDate: Date?
    private static let cacheTTL: TimeInterval = 1.0

    /// 显式语言覆盖：设置后 isEnglish() 恒返回该语言,不再读盘、不受 TTL 影响。
    /// 测试(TestRunner/swift-testing)用它固定语言环境——TTL 过期重读会令紧邻两次
    /// tr() 在「配置文件出现/消失」的边界上返回不同语言,跨调用比较必然偶发翻转。
    public static var languageOverride: AppLanguage?

    public static func isEnglish() -> Bool {
        if let o = languageOverride { return o == .en }
        if let c = cachedLanguage, let d = cacheDate, Date().timeIntervalSince(d) < cacheTTL { return c == .en }
        let lang = resolveLanguage()
        cachedLanguage = lang
        cacheDate = Date()
        return lang == .en
    }

    /// `.system` 按当前 Locale 解析,同一答案写进缓存,保证缓存命中路径与读盘路径一致。
    private static func resolveLanguage() -> AppLanguage {
        let raw: String
        if let data = try? Data(contentsOf: ConfigStore.configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let lang = json["language"] as? String {
            raw = lang
        } else {
            raw = "system"
        }
        let lang: AppLanguage = AppLanguage(rawValue: raw) ?? .system
        if lang == .system {
            return Locale.current.language.languageCode?.identifier == "zh" ? .zh : .en
        }
        return lang
    }

    public static func invalidateCache() { cachedLanguage = nil; cacheDate = nil }

    public static func tr(_ zh: String, _ en: String) -> String {
        isEnglish() ? en : zh
    }


    private static let tmplNameMap: [String:String] = [
        "文本文件": "Text File",
        "Markdown 文档": "Markdown Document",
        "Word 文档": "Word Document",
        "Excel 表格": "Excel Spreadsheet",
        "Python 脚本": "Python Script",
        "Shell 脚本": "Shell Script",
        "JSON 文件": "JSON File",
        "HTML 文件": "HTML File",
        "Swift 文件": "Swift File",
        "新模板": "New Template"
    ]
    private static let tmplFileMap: [String:String] = [
        "新建文本.txt": "New Text.txt",
        "新建文档.md": "New Document.md",
        "新建 Word 文档.docx": "New Word Document.docx",
        "新建 Excel 表格.xlsx": "New Excel Spreadsheet.xlsx",
        "新建文件.txt": "New File.txt"
    ]
    public static func tmplName(_ zh: String) -> String {
        isEnglish() ? (tmplNameMap[zh] ?? zh) : zh
    }
    public static func tmplFile(_ zh: String) -> String {
        isEnglish() ? (tmplFileMap[zh] ?? zh) : zh
    }

    public static var appName: String { tr("极简工具箱", "FlowBox") }
    public static var settings: String { tr("设置", "Settings") }
    public static var enabled: String { tr("启用", "Enabled") }
    public static var disabled: String { tr("禁用", "Disabled") }
}
