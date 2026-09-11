import Testing
import SharedCore

/// 状态项「窗口 ↔ 应用身份」的配对规则：跨屏副本命名 + 位置键宽度自检。
///
/// 两条都必须是**宁缺毋滥**的推断 —— 名字配错会让用户以为点错了 App。
@Suite("StatusItemPairing")
struct StatusItemPairingTests {

    @Test func anonymousNamesAreNotIdentities() {
        #expect(!StatusItemPairing.isIdentifiableName(""))
        #expect(!StatusItemPairing.isIdentifiableName("   "))
        #expect(!StatusItemPairing.isIdentifiableName("Item-0"))
        #expect(!StatusItemPairing.isIdentifiableName("Item-12"))
    }

    @Test func usableNamesAreIdentities() {
        #expect(StatusItemPairing.isIdentifiableName("com.tencent.qq"))
        #expect(StatusItemPairing.isIdentifiableName("WiFi"))
        #expect(StatusItemPairing.isIdentifiableName("ndsc-gui"))
        #expect(StatusItemPairing.isIdentifiableName(" 电池 "))
    }

    @Test func onlyBundleIDFormsAreLookedUp() {
        // 只有 bundle id 形态才该去查应用名：`WiFi` 走模糊匹配会被 WiFiSpoof 之类串味
        #expect(StatusItemPairing.looksLikeBundleID("com.tencent.qq"))
        #expect(StatusItemPairing.looksLikeBundleID("io.github.clash-verge-rev.clash-verge-rev"))
        #expect(!StatusItemPairing.looksLikeBundleID("WiFi"))
        #expect(!StatusItemPairing.looksLikeBundleID("Bento Box.1"))
    }

    /// 本机实测形态：主屏 7 个匿名 `Item-0`，外接屏同 7 个带 bundle id，两侧宽度序列一致。
    @Test func crossScreenNamingMapsAnonymousItems() {
        let anon = [
            StatusWindow(number: 8203, x: 880,  width: 38, name: "Item-0"),
            StatusWindow(number: 7789, x: 918,  width: 32, name: "Item-0"),
            StatusWindow(number: 55,   x: 950,  width: 32, name: "Item-0"),
            StatusWindow(number: 8852, x: 982,  width: 38, name: "Item-0"),
            StatusWindow(number: 91,   x: 1020, width: 34, name: "Item-0"),
            StatusWindow(number: 52,   x: 1054, width: 44, name: "Item-0"),
            StatusWindow(number: 95,   x: 1098, width: 38, name: "Item-0"),
        ]
        let named = [
            StatusWindow(number: 8619, x: 2798, width: 38, name: "com.tencent.workbuddy.mac"),
            StatusWindow(number: 8617, x: 2836, width: 32, name: "com.tencent.qq"),
            StatusWindow(number: 8608, x: 2868, width: 32, name: "com.apple.Spotlight"),
            StatusWindow(number: 8854, x: 2900, width: 38, name: "com.tencent.xinWeChat"),
            StatusWindow(number: 8610, x: 2938, width: 34, name: "io.github.clash-verge-rev.clash-verge-rev"),
            StatusWindow(number: 8607, x: 2972, width: 44, name: "com.apple.TextInputMenuAgent"),
            StatusWindow(number: 8614, x: 3016, width: 38, name: "ndsc-gui"),
        ]
        let m = StatusItemPairing.crossScreenNames(recipients: anon, donors: named)
        #expect(m.count == 7)
        // 宽度是硬约束：同为匿名的 QQ 与 Spotlight（都 32 宽）靠 x 顺序区分
        #expect(m[7789] == "com.tencent.qq")
        #expect(m[8203] == "com.tencent.workbuddy.mac")
        #expect(m[8852] == "com.tencent.xinWeChat")
        #expect(m[91] == "io.github.clash-verge-rev.clash-verge-rev")
        #expect(m[95] == "ndsc-gui")
    }

    @Test func abortsWhenCountsDiffer() {
        let anon = [StatusWindow(number: 1, x: 10, width: 32, name: "Item-0")]
        let named = [StatusWindow(number: 2, x: 90, width: 32, name: "com.a.b"),
                     StatusWindow(number: 3, x: 80, width: 32, name: "com.c.d")]
        #expect(StatusItemPairing.crossScreenNames(recipients: anon, donors: named).isEmpty)
    }

    @Test func abortsWhenWidthsDiffer() {
        let anon = [StatusWindow(number: 1, x: 10, width: 32, name: "Item-0")]
        let named = [StatusWindow(number: 2, x: 90, width: 44, name: "com.a.b")]
        #expect(StatusItemPairing.crossScreenNames(recipients: anon, donors: named).isEmpty)
    }

    @Test func abortsOnNameConflict() {
        // 同宽组内两侧名字冲突 → 整批错位，一个都不猜
        let r = [StatusWindow(number: 1, x: 10, width: 38, name: "com.a.one"),
                 StatusWindow(number: 2, x: 20, width: 38, name: "com.b.two")]
        let d = [StatusWindow(number: 3, x: 80, width: 38, name: "com.b.two"),
                 StatusWindow(number: 4, x: 90, width: 38, name: "com.a.one")]
        #expect(StatusItemPairing.crossScreenNames(recipients: r, donors: d).isEmpty)
    }

    /// 另一种实测形态：主屏只剩 4 个空名系统项，名字落在副屏副本上。
    @Test func namesSystemItemsFromOtherScreen() {
        let emptyR = [StatusWindow(number: 1136, x: 1136, width: 38,  name: ""),
                      StatusWindow(number: 1174, x: 1174, width: 71,  name: ""),
                      StatusWindow(number: 1321, x: 1321, width: 42,  name: ""),
                      StatusWindow(number: 1363, x: 1363, width: 151, name: "")]
        let sysD = [StatusWindow(number: 3054, x: 3054, width: 38,  name: "WiFi"),
                    StatusWindow(number: 3092, x: 3092, width: 71,  name: "Battery"),
                    StatusWindow(number: 3239, x: 3239, width: 42,  name: "BentoBox-0"),
                    StatusWindow(number: 3281, x: 3281, width: 151, name: "Clock")]
        let m = StatusItemPairing.crossScreenNames(recipients: emptyR, donors: sysD)
        #expect(m.count == 4)
        #expect(m[1174] == "Battery")
        #expect(m[1363] == "Clock")
    }

    @Test func widthCheckRejectsStaleKeyButSkipsUnknown() {
        let w32 = StatusWindow(number: 7, x: 918, width: 32, name: "Item-0")
        #expect(StatusItemPairing.widthsConsistent([(w32, "com.tencent.qq")],
                                                  knownWidths: ["com.tencent.qq": 32]))
        // 残留键把宽度 38 的微信键安到 32 宽的窗口上 → 否决整批
        #expect(!StatusItemPairing.widthsConsistent([(w32, "com.tencent.xinWeChat")],
                                                   knownWidths: ["com.tencent.xinwechat": 38]))
        // 宽度未知（未运行/未观测到）→ 跳过检查，不因此否决
        #expect(StatusItemPairing.widthsConsistent([(w32, "com.aiproxy.menubar")], knownWidths: [:]))
    }

    /// 2026-09-11 实测翻车场景:插拔副屏后主屏把同宽的 QQ/Spotlight 互换、副屏镜像保持旧序,
    /// 顺序对齐把两位身份对调。可见位 7789 的 AX 真身是 QQ → 与同宽的 55 交换配对。
    @Test func anchorReconcileSwapsMispairedSameWidthItems() {
        let pairing = [7789: "com.apple.Spotlight", 55: "com.tencent.qq"]
        let anchors = [7789: "com.tencent.qq"]   // 只有可见位能 AX 命中
        let widths = [7789: 32.0, 55: 32.0]
        let fixed = StatusItemPairing.reconcileAnchors(pairing, anchors: anchors, widths: widths)
        #expect(fixed[7789] == "com.tencent.qq")
        #expect(fixed[55] == "com.apple.Spotlight")
    }

    @Test func anchorReconcileLeavesAgreeingOrDifferentWidthPairs() {
        // 锚点与配对一致 / anchors 为空 → 原样
        let pairing = [7789: "com.tencent.qq", 55: "com.apple.Spotlight"]
        #expect(StatusItemPairing.reconcileAnchors(pairing, anchors: [7789: "com.tencent.qq"],
                                                   widths: [7789: 32, 55: 32]) == pairing)
        #expect(StatusItemPairing.reconcileAnchors(pairing, anchors: [:],
                                                   widths: [7789: 32, 55: 32]) == pairing)
        // 真身配在别的窗口上但两者宽度不同 → 宽度是硬约束,不许换
        let diffWidth = [8852: "com.b.x", 55: "com.a.y"]
        let kept = StatusItemPairing.reconcileAnchors(diffWidth, anchors: [8852: "com.a.y"],
                                                      widths: [8852: 38, 55: 32])
        #expect(kept == diffWidth)
    }
}
