import Darwin
import Foundation

/// 扩展 → 宿主 App 的命令协议(URL scheme)。
/// 扩展沙盒内做文件写入/AppleScript 受限,由不受沙盒限制的宿主 App 执行实际操作。
public enum RCCommand {

    public static let scheme = "flowbox"

    static func url(host: String, query: [URLQueryItem]) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = query
        return components.url
    }

    /// 复制文本到剪贴板
    public static func copy(text: String) -> URL? {
        url(host: "copy", query: [URLQueryItem(name: "text", value: text)])
    }

    /// 在终端中打开目录
    public static func terminal(dir: String) -> URL? {
        url(host: "terminal", query: [URLQueryItem(name: "dir", value: dir)])
    }

    /// 按配置序号新建文件
    public static func newFile(dir: String, index: Int) -> URL? {
        url(host: "newfile", query: [
            URLQueryItem(name: "dir", value: dir),
            URLQueryItem(name: "index", value: String(index)),
        ])
    }

    /// 去除隔离属性(单个或多个路径用 \n 分隔,宿主端执行 xattr -dr)
    public static func stripQuarantine(paths: [String]) -> URL? {
        guard !paths.isEmpty else { return nil }
        return url(host: "qxattr", query: [URLQueryItem(name: "paths", value: paths.joined(separator: "\n"))])
    }

    /// 一键扫描 /Applications 去隔离(不带参数)
    public static func stripQuarantineSweep() -> URL? {
        url(host: "qxattr", query: [URLQueryItem(name: "sweep", value: "1")])
    }
}

/// 配置文件位置约定:
/// macOS 13+ 要求 Finder 扩展必须沙盒化,否则 PlugInKit 会拒绝收录
/// ("plug-ins must be sandboxed")。扩展沙盒后只能读写自己的容器目录,
/// 因此配置统一放在扩展容器内;宿主 App 未沙盒,可直接读写同一路径。
public enum ConfigStore {

    /// 扩展的 bundle id,须与 build.sh 中 EXT_BUNDLE_ID 一致
    public static let extBundleID = "net.ai2048.flowbox.ext"

    /// 历史 bundle id(Bundle ID 从 com.ysd.flowbox 迁移到 net.ai2048.flowbox 时,
    /// 旧容器里的用户配置需要搬过来,否则升级后设置会丢)
    private static let legacyExtBundleIDs = ["com.ysd.flowbox.ext"]

    /// 首次启动时把旧容器的 config.json 搬到新容器(只搬一次:新配置已存在则跳过)
    static func migrateLegacyConfigIfNeeded() {
        let fm = FileManager.default
        let newURL = configURL
        if fm.fileExists(atPath: newURL.path) { return }
        for legacy in legacyExtBundleIDs {
            let legacyURL = URL(fileURLWithPath: realHomePath, isDirectory: true)
                .appendingPathComponent("Library/Containers/\(legacy)/Data")
                .appendingPathComponent("Library/Application Support/FlowBox/config.json")
            guard fm.fileExists(atPath: legacyURL.path) else { continue }
            do {
                try fm.createDirectory(
                    at: newURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fm.copyItem(at: legacyURL, to: newURL)
            } catch { continue }
            break
        }
    }

    /// 真实用户主目录(扩展进程内 NSHomeDirectory 指向容器,须从 passwd 取真实路径)
    public static var realHomePath: String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    public static var configURL: URL {
        URL(fileURLWithPath: realHomePath, isDirectory: true)
            .appendingPathComponent("Library/Containers/\(extBundleID)/Data")
            .appendingPathComponent("Library/Application Support/FlowBox/config.json")
    }
}

/// 「新建文件」菜单里的一项
public struct NewFileItem: Codable, Equatable {
    /// 菜单显示名,如 "Markdown 文档"
    public var name: String
    /// 新建文件的文件名,如 "新建文档.md"
    public var filename: String
    /// 文件初始内容(模板);纯文本,或 encoding 为 base64 时的二进制内容
    public var content: String
    /// 内容编码:utf8(默认,纯文本)或 base64(docx/xlsx 等二进制模板)
    public var encoding: String?
    /// 是否在菜单中显示
    public var enabled: Bool

    public var isBase64: Bool { encoding == "base64" }
    public var displayName: String { L10n.tmplName(name) }
    public var displayFilename: String { L10n.tmplFile(filename) }

    public init(
        name: String,
        filename: String,
        content: String,
        enabled: Bool = true,
        encoding: String? = nil
    ) {
        self.name = name
        self.filename = filename
        self.content = content
        self.enabled = enabled
        self.encoding = encoding
    }

    enum CodingKeys: String, CodingKey {
        case name, filename, content, encoding, enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        filename = try c.decode(String.self, forKey: .filename)
        content = try c.decode(String.self, forKey: .content)
        encoding = try c.decodeIfPresent(String.self, forKey: .encoding)
        // 旧配置没有 enabled 字段,默认启用
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

/// 右键菜单中各功能项的显示开关
public struct MenuVisibility: Codable, Equatable {
    public var copyFolder = true
    public var copySelection = true
    public var openTerminal = true
    public var newFile = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case copyFolder, copySelection, openTerminal, newFile
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        copyFolder = try c.decodeIfPresent(Bool.self, forKey: .copyFolder) ?? true
        copySelection = try c.decodeIfPresent(Bool.self, forKey: .copySelection) ?? true
        openTerminal = try c.decodeIfPresent(Bool.self, forKey: .openTerminal) ?? true
        newFile = try c.decodeIfPresent(Bool.self, forKey: .newFile) ?? true
    }
}

/// 鼠标相关设置
public struct ScrollConfig: Codable, Equatable {
    /// 反转外接鼠标滚轮方向(触控板不受影响)
    public var reverseMouseWheel = false
    /// 平滑滚动:把离散滚轮事件转成连续的流畅滚动
    public var smoothScrolling = false
    /// 最短步长:控制单次滚动的最短距离(以 60 为中性基准缩放输入像素量)
    public var minStep: Double = 60

    public init() {}

    enum CodingKeys: String, CodingKey {
        case reverseMouseWheel, smoothScrolling, minStep
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 旧配置缺少的字段用默认值兜底,避免整体解码失败丢掉模板数据
        reverseMouseWheel = try c.decodeIfPresent(Bool.self, forKey: .reverseMouseWheel) ?? false
        smoothScrolling = try c.decodeIfPresent(Bool.self, forKey: .smoothScrolling) ?? false
        minStep = try c.decodeIfPresent(Double.self, forKey: .minStep) ?? 60
    }
}

/// 菜单栏收纳设置
public struct MenuBarConfig: Codable, Equatable {
    /// 是否启用菜单栏图标收纳(分隔线 + 箭头,类似 Hidden Bar / Bartender)
    public var hiderEnabled = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case hiderEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hiderEnabled = try c.decodeIfPresent(Bool.self, forKey: .hiderEnabled) ?? false
    }
}

/// 去隔离面板配置(纯手动,无自动监听)
public struct QuarantineConfig: Codable, Equatable {
    public init() {}
}

/// 人脸检测自动锁屏设置(纯本地 Vision 检测,不联网不存图)
public struct PresenceConfig: Codable, Equatable {
    /// 是否启用「离开自动锁屏」
    public var enabled = false
    /// 无操作多少秒后标记疑似离开(3~30)
    public var lockAfterSeconds: Double = 8
    /// 空闲多少秒后开摄像头做一次人脸确认(10~300)
    public var confirmAfterSeconds: Double = 60
    /// 开启/解锁后的宽限期(秒),避免刚输完密码就被锁
    public var gracePeriod: Double = 15
    /// 确认无人、即将锁屏时,把那一刻摄像头快照存到本地(排查误锁用);画面仅留本机
    public var saveCaptureOnLock = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case enabled, lockAfterSeconds, confirmAfterSeconds, gracePeriod, saveCaptureOnLock
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        lockAfterSeconds = try c.decodeIfPresent(Double.self, forKey: .lockAfterSeconds) ?? 8
        confirmAfterSeconds = try c.decodeIfPresent(Double.self, forKey: .confirmAfterSeconds) ?? 60
        gracePeriod = try c.decodeIfPresent(Double.self, forKey: .gracePeriod) ?? 15
        saveCaptureOnLock = try c.decodeIfPresent(Bool.self, forKey: .saveCaptureOnLock) ?? true
    }
}

/// 截图设置
public struct ScreenshotConfig: Codable, Equatable {
    /// 全局快捷键(Carbon 虚拟键码 + 修饰键掩码),默认 ⌥A
    public var hotKeyCode: Int = 0          // kVK_ANSI_A
    public var hotKeyModifiers: Int = 2048  // optionKey
    /// 画笔颜色(#RRGGBB)
    public var penColorHex: String = "#FF3B30"
    /// 画笔宽度(点)
    public var penWidth: Double = 4
    /// 马赛克块大小(背景图像素,Retina 下实际显示为其一半)
    public var mosaicBlock: Double = 16

    public init() {}

    enum CodingKeys: String, CodingKey {
        case hotKeyCode, hotKeyModifiers, penColorHex, penWidth, mosaicBlock
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotKeyCode = try c.decodeIfPresent(Int.self, forKey: .hotKeyCode) ?? 0
        hotKeyModifiers = try c.decodeIfPresent(Int.self, forKey: .hotKeyModifiers) ?? 2048
        penColorHex = try c.decodeIfPresent(String.self, forKey: .penColorHex) ?? "#FF3B30"
        penWidth = try c.decodeIfPresent(Double.self, forKey: .penWidth) ?? 4
        mosaicBlock = try c.decodeIfPresent(Double.self, forKey: .mosaicBlock) ?? 16
    }
}

/// 录屏设置(全屏 + 带声)
public struct RecordingConfig: Codable, Equatable {
    /// 全局快捷键,默认 ⌥R (kVK_ANSI_R = 15)
    public var hotKeyCode: Int = 15
    public var hotKeyModifiers: Int = 2048  // optionKey
    /// 是否录制系统声音(跟随画面声音)
    public var captureSystemAudio = true
    /// 是否录制麦克风
    public var captureMicrophone = true
    /// 帧率
    public var frameRate: Int = 30
    /// 是否叠加摄像头画中画
    public var captureCamera = false
    /// 摄像头画中画宽度(点,160~360)
    public var cameraWidth: Double = 220
    /// 摄像头归一化位置(0~1,相对主屏; -1 表示首次自动靠右下)
    public var cameraX: Double = -1
    public var cameraY: Double = -1
    /// 摄像头是否圆形裁切
    public var cameraIsCircle = true
    /// 摄像头是否镜像(前置常用)
    public var cameraMirrored = true

    public init() {}

    enum CodingKeys: String, CodingKey {
        case hotKeyCode, hotKeyModifiers, captureSystemAudio, captureMicrophone, frameRate,
             captureCamera, cameraWidth, cameraX, cameraY, cameraIsCircle, cameraMirrored
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hotKeyCode = try c.decodeIfPresent(Int.self, forKey: .hotKeyCode) ?? 15
        hotKeyModifiers = try c.decodeIfPresent(Int.self, forKey: .hotKeyModifiers) ?? 2048
        captureSystemAudio = try c.decodeIfPresent(Bool.self, forKey: .captureSystemAudio) ?? true
        captureMicrophone = try c.decodeIfPresent(Bool.self, forKey: .captureMicrophone) ?? true
        frameRate = try c.decodeIfPresent(Int.self, forKey: .frameRate) ?? 30
        captureCamera = try c.decodeIfPresent(Bool.self, forKey: .captureCamera) ?? false
        cameraWidth = try c.decodeIfPresent(Double.self, forKey: .cameraWidth) ?? 220
        cameraX = try c.decodeIfPresent(Double.self, forKey: .cameraX) ?? -1
        cameraY = try c.decodeIfPresent(Double.self, forKey: .cameraY) ?? -1
        cameraIsCircle = try c.decodeIfPresent(Bool.self, forKey: .cameraIsCircle) ?? true
        cameraMirrored = try c.decodeIfPresent(Bool.self, forKey: .cameraMirrored) ?? true
    }
}

public struct AppConfig: Codable, Equatable {
    public var language: String
    public var menu: MenuVisibility
    public var scroll: ScrollConfig
    public var menuBar: MenuBarConfig
    public var screenshot: ScreenshotConfig
    public var recording: RecordingConfig
    public var quarantine: QuarantineConfig
    public var presence: PresenceConfig
    public var newFiles: [NewFileItem]

    public init(
        language: String = "system",
        menu: MenuVisibility = MenuVisibility(),
        scroll: ScrollConfig = ScrollConfig(),
        menuBar: MenuBarConfig = MenuBarConfig(),
        screenshot: ScreenshotConfig = ScreenshotConfig(),
        recording: RecordingConfig = RecordingConfig(),
        quarantine: QuarantineConfig = QuarantineConfig(),
        presence: PresenceConfig = PresenceConfig(),
        newFiles: [NewFileItem]
    ) {
        self.language = language
        self.menu = menu
        self.scroll = scroll
        self.menuBar = menuBar
        self.screenshot = screenshot
        self.recording = recording
        self.quarantine = quarantine
        self.presence = presence
        self.newFiles = newFiles
    }

    enum CodingKeys: String, CodingKey {
        case language, menu, scroll, menuBar, screenshot, recording, quarantine, presence, newFiles
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "system"
        menu = try c.decodeIfPresent(MenuVisibility.self, forKey: .menu) ?? MenuVisibility()
        scroll = try c.decodeIfPresent(ScrollConfig.self, forKey: .scroll) ?? ScrollConfig()
        menuBar = try c.decodeIfPresent(MenuBarConfig.self, forKey: .menuBar) ?? MenuBarConfig()
        screenshot = try c.decodeIfPresent(ScreenshotConfig.self, forKey: .screenshot) ?? ScreenshotConfig()
        recording = try c.decodeIfPresent(RecordingConfig.self, forKey: .recording) ?? RecordingConfig()
        quarantine = try c.decodeIfPresent(QuarantineConfig.self, forKey: .quarantine) ?? QuarantineConfig()
        presence = try c.decodeIfPresent(PresenceConfig.self, forKey: .presence) ?? PresenceConfig()
        newFiles = try c.decodeIfPresent([NewFileItem].self, forKey: .newFiles) ?? []
    }

    // MARK: - 读取 / 写入

    /// 读取配置;文件不存在或损坏时写入并返回默认配置。
    public static func load() -> AppConfig {
        ConfigStore.migrateLegacyConfigIfNeeded()
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return config
        }
        let config = defaultConfig()
        config.write()
        return config
    }

    public static var configURL: URL {
        ConfigStore.configURL
    }

    public func write() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(
            at: ConfigStore.configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: ConfigStore.configURL, options: .atomic)
    }

    public static func defaultConfig() -> AppConfig {
        AppConfig(newFiles: [
            NewFileItem(name: "文本文件", filename: "新建文本.txt", content: ""),
            NewFileItem(name: "Markdown 文档", filename: "新建文档.md", content: "# 标题\n\n"),
            NewFileItem(
                name: "Word 文档",
                filename: "新建 Word 文档.docx",
                content: "UEsDBBQAAAAIAJxUG115bjPX6AAAAK0BAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbH1QyU7DMBD9FWuuKHHggBCK0wPLETiUDxjZk8SqN3nc0v49Tlt6QIXjzFv1+tXeO7GjzDYGBbdtB4KCjsaGScHn+rV5AMEFg0EXAyk4EMNq6NeHRCyqNrCCuZT0KCXrmTxyGxOFiowxeyz1zJNMqDc4kbzrunupYygUSlMWDxj6Zxpx64p42df3qUcmxyCeTsQlSwGm5KzGUnG5C+ZXSnNOaKvyyOHZJr6pBJBXExbk74Cz7r0Ok60h8YG5vKGvLPkVs5Em6q2vyvZ/mys94zhaTRf94pZy1MRcF/euvSAebfjpL49zD99QSwMEFAAAAAgAnFQbXZv9N+qtAAAAKQEAAAsAAABfcmVscy8ucmVsc43POw7CMAwG4KtE3mlaBoRQ0y4IqSsqB7ASN61oHkrCo7cnAwNFDIy2f3+W6/ZpZnanECdnBVRFCYysdGqyWsClP232wGJCq3B2lgQsFKFt6jPNmPJKHCcfWTZsFDCm5A+cRzmSwVg4TzZPBhcMplwGzT3KK2ri27Lc8fBpwNpknRIQOlUB6xdP/9huGCZJRydvhmz6ceIrkWUMmpKAhwuKq3e7yCzwpuarF5sXUEsDBBQAAAAIAJxUG12ZCVxZiwAAAK4AAAARAAAAd29yZC9kb2N1bWVudC54bWxFjUEOgjAQRa9CZi+DLowhFHaeQA9Q2xFI6EzTqSK3tyyMq5+Xn7zXDZ+wVG9KOgsbONYNVMRO/MyjgfvterhApdmyt4swGdhIYei7tfXiXoE4V0XA2q4Gppxji6huomC1lkhcvqekYHPBNOIqycckjlSLPyx4apozBjsz7MqH+G3fiH2HP8R/qv8CUEsBAhQDFAAAAAgAnFQbXXluM9foAAAArQEAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACACcVBtdm/036q0AAAApAQAACwAAAAAAAAAAAAAAgAEZAQAAX3JlbHMvLnJlbHNQSwECFAMUAAAACACcVBtdmQlcWYsAAACuAAAAEQAAAAAAAAAAAAAAgAHvAQAAd29yZC9kb2N1bWVudC54bWxQSwUGAAAAAAMAAwC5AAAAqQIAAAAA",
                encoding: "base64"
            ),
            NewFileItem(
                name: "Excel 表格",
                filename: "新建 Excel 表格.xlsx",
                content: "UEsDBBQAAAAIAJxUG11uYbgN/gAAAC0CAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbK2RzU7DMBCEX8XytYqdckAIJe2BnyNwKA+w2JvEiv/kdUv69jhp4YAKXDit7JnZb2Q328lZdsBEJviWr0XNGXoVtPF9y193j9UNZ5TBa7DBY8uPSHy7aXbHiMRK1lPLh5zjrZSkBnRAIkT0RelCcpDLMfUyghqhR3lV19dSBZ/R5yrPO/imuccO9jazh6lcn3oktMTZ3ck4s1oOMVqjIBddHrz+RqnOBFGSi4cGE2lVDFxeJMzKz4Bz7rk8TDIa2Quk/ASuuORk5XtI41sIo/h9yYWWoeuMQh3U3pWIoJgQNA2I2VmxTOHA+NXf/MVMchnrfy7ytf+zh1y+e/MBUEsDBBQAAAAIAJxUG12Y2uuLrgAAACcBAAALAAAAX3JlbHMvLnJlbHONz8EOgjAMBuBXWXqXgQdjDIOLMeFq8AHmVgYB1mWbCm/vjmI8eGz69/vTsl7miT3Rh4GsgCLLgaFVpAdrBNzay+4ILERptZzIooAVA9RVecVJxnQS+sEFlgwbBPQxuhPnQfU4y5CRQ5s2HflZxjR6w51UozTI93l+4P7TgK3JGi3AN7oA1q4O/7Gp6waFZ1KPGW38UfGVSLL0BqOAZeIv8uOdaMwSCrwq+ebB6g1QSwMEFAAAAAgAnFQbXZ1sQ725AAAAGwEAAA8AAAB4bC93b3JrYm9vay54bWyNT0uuwjAMvErkPaRlgZ6qtmwQEmvgAKFxaURjV3b4vNsTfntWM9ZoxjP16h5Hc0XRwNRAOS/AIHXsA50aOOw3sz8wmhx5NzJhA/+osGrrG8v5yHw22U7awJDSVFmr3YDR6ZwnpKz0LNGlfMrJ6iTovA6IKY52URRLG10geCdU8ksG933ocM3dJSKld4jg6FIur0OYFNr69UE/aMjFXHr35GUe8sStzzvBSBUyka0vwba1/drsd1n7AFBLAwQUAAAACACcVBtdWv2Ca7EAAAAoAQAAGgAAAHhsL19yZWxzL3dvcmtib29rLnhtbC5yZWxzjc/JCsJADAbgVxlyt2k9iEinXkToVeoDDNN0oZ2Fybj07R08iAUPnkLyky+kPD7NLO4UeHRWQpHlIMhq1462l3Btzps9CI7Ktmp2liQsxHCsygvNKqYVHkbPIhmWJQwx+gMi64GM4sx5sinpXDAqpjb06JWeVE+4zfMdhm8D1qaoWwmhbgsQzeLpH9t13ajp5PTNkI0/TuDDhYkHophQFXqKEj4jxncpsqQCViWuPqxeUEsDBBQAAAAIAJxUG12ejKhOggAAAJwAAAAYAAAAeGwvd29ya3NoZWV0cy9zaGVldDEueG1sPYxLDsIwDAWvEnlPHVgghJJ0gzgBHMBqTFvROFUc8bk9URcs34zmuf6TFvPionMWD/vOgmEZcpxl9HC/XXcnMFpJIi1Z2MOXFfrg3rk8dWKupvWiHqZa1zOiDhMn0i6vLM08cklU2ywj6lqY4halBQ/WHjHRLBDcxi5UCYPD/3P4AVBLAQIUAxQAAAAIAJxUG11uYbgN/gAAAC0CAAATAAAAAAAAAAAAAACAAQAAAABbQ29udGVudF9UeXBlc10ueG1sUEsBAhQDFAAAAAgAnFQbXZja64uuAAAAJwEAAAsAAAAAAAAAAAAAAIABLwEAAF9yZWxzLy5yZWxzUEsBAhQDFAAAAAgAnFQbXZ1sQ725AAAAGwEAAA8AAAAAAAAAAAAAAIABBgIAAHhsL3dvcmtib29rLnhtbFBLAQIUAxQAAAAIAJxUG11a/YJrsQAAACgBAAAaAAAAAAAAAAAAAACAAewCAAB4bC9fcmVscy93b3JrYm9vay54bWwucmVsc1BLAQIUAxQAAAAIAJxUG12ejKhOggAAAJwAAAAYAAAAAAAAAAAAAACAAdUDAAB4bC93b3Jrc2hlZXRzL3NoZWV0MS54bWxQSwUGAAAAAAUABQBFAQAAjQQAAAAA",
                encoding: "base64"
            ),
            NewFileItem(name: "Python 脚本", filename: "script.py", content: "#!/usr/bin/env python3\n"),
            NewFileItem(name: "Shell 脚本", filename: "script.sh", content: "#!/bin/bash\n"),
            NewFileItem(name: "JSON 文件", filename: "data.json", content: "{\n  \n}\n"),
            NewFileItem(
                name: "HTML 文件",
                filename: "index.html",
                content: "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n  <meta charset=\"UTF-8\">\n  <title>标题</title>\n</head>\n<body>\n\n</body>\n</html>\n"
            ),
            NewFileItem(name: "Swift 文件", filename: "Main.swift", content: "import Foundation\n\n"),
        ])
    }
}
