import Testing
import CoreGraphics
@testable import SharedCore

@Suite("MenuRowLayout")
struct MenuRowLayoutTests {

    @Test func iconOnlyRowFallsBackToMinimumWidth() {
        // 纯图标行(没有文字)不能算成 0 宽
        #expect(MenuRowLayout.unifiedWidth(widestTitle: 0) == MenuRowLayout.defaultMinimumWidth)
    }

    @Test func narrowTitleStillGetsMinimumWidth() {
        #expect(MenuRowLayout.unifiedWidth(widestTitle: 10) == MenuRowLayout.defaultMinimumWidth)
    }

    @Test func wideTitleDrivesRowWidth() {
        let expected = MenuRowLayout.titleOriginX + 200 + MenuRowLayout.trailingInset
        #expect(MenuRowLayout.unifiedWidth(widestTitle: 200) == expected)
    }

    @Test func veryLongTitleIsClamped() {
        #expect(MenuRowLayout.unifiedWidth(widestTitle: 5000) == MenuRowLayout.defaultMaximumWidth)
    }

    @Test func titleOriginAccountsForIconColumn() {
        #expect(MenuRowLayout.titleOriginX ==
                MenuRowLayout.iconLeading + MenuRowLayout.iconSide + MenuRowLayout.titleGap)
    }

    @Test func negativeWidthTreatedAsNoText() {
        #expect(MenuRowLayout.unifiedWidth(widestTitle: -50) == MenuRowLayout.defaultMinimumWidth)
    }

    @Test func iconFitsInsideRow() {
        // 大图标列表观感:图标要完整落在行内还留呼吸位
        #expect(MenuRowLayout.rowHeight >= MenuRowLayout.iconSide + 8)
    }

    @Test func titleStaysSmallerThanIcon() {
        #expect(MenuRowLayout.titleFontSize < MenuRowLayout.iconSide)
    }
}
