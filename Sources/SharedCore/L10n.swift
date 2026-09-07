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

    public static func isEnglish() -> Bool {
        if let c = cachedLanguage, let d = cacheDate, Date().timeIntervalSince(d) < cacheTTL { return c == .en }
        let raw: String
        if let data = try? Data(contentsOf: ConfigStore.configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let lang = json["language"] as? String {
            raw = lang
        } else {
            raw = "system"
        }
        let lang: AppLanguage = AppLanguage(rawValue: raw) ?? .system
        cachedLanguage = lang
        cacheDate = Date()
        if lang == .zh { return false }
        if lang == .en { return true }
        return Locale.current.language.languageCode?.identifier != "zh"
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
