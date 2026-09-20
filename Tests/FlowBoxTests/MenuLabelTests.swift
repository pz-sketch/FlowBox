import Testing
import SharedCore

@Suite("MenuLabel")
struct MenuLabelTests {

    init() {
        // 固定语言环境,期望值不随 CI/本机配置或 L10n 缓存 TTL 翻转
        L10n.languageOverride = .en
    }

    @Test func dropsMachineIdentifiers() {
        // 状态项的窗口名经常是域名 / bundle id / autosaveName —— 都不是人话
        #expect(MenuLabel.displayable("omlx.metric.live") == "")
        #expect(MenuLabel.displayable("com.tencent.xinWeChat") == "")
        #expect(MenuLabel.displayable("BentoBox-0") == "")
        #expect(MenuLabel.displayable("WiFi") == "")
        #expect(MenuLabel.displayable("12345") == "")
    }

    @Test func keepsHumanReadableTitles() {
        #expect(MenuLabel.displayable("聚焦") == "聚焦")
        #expect(MenuLabel.displayable("  电池  ") == "电池")
        #expect(MenuLabel.displayable("微信 WeChat") == "微信 WeChat")
    }

    @Test func handlesEmptyInput() {
        #expect(MenuLabel.displayable("") == "")
        #expect(MenuLabel.displayable("   ") == "")
    }

    @Test func detectsCJK() {
        #expect(MenuLabel.containsCJK("输入法"))
        #expect(MenuLabel.containsCJK("微信 3"))
        #expect(!MenuLabel.containsCJK("Autofill"))
        #expect(!MenuLabel.containsCJK(""))
    }

    @Test func fallbackTitleNeverEmpty() {
        // 用户要求:不许出现 `?`/空标题行,包名/窗口名都可以显示
        // 语言已由 suite 固定为英文,期望值写死
        #expect(MenuLabel.fallbackTitle(winName: "com.tencent.qq", bundleID: nil, windowNumber: 1) == "com.tencent.qq")
        #expect(MenuLabel.fallbackTitle(winName: "  电池  ", bundleID: nil, windowNumber: 2) == "电池")
        #expect(MenuLabel.fallbackTitle(winName: "Item-0", bundleID: nil, windowNumber: 8617) == "Menu bar icon 8617")
        #expect(MenuLabel.fallbackTitle(winName: "", bundleID: "com.tencent.qq", windowNumber: 3) == "com.tencent.qq")
        #expect(MenuLabel.fallbackTitle(winName: "", bundleID: nil, windowNumber: 4) == "Menu bar icon 4")
    }
}
