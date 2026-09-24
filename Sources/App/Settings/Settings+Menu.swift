import AppKit
import AVFoundation
import SharedCore
import Carbon.HIToolbox
import os

extension SettingsWindowController {
    func buildMenuTab(tabView: NSTabView) {
        let stack = UIStyle.makeTab(tabView, identifier: "menu", label: L10n.tr("菜单", "Menu"))

        // ========== 右键菜单 ==========
        stack.addArrangedSubview(sectionHeader(
            L10n.tr("菜单", "Menu"),
            subtitle: L10n.tr("选择要在 Finder 右键中显示的功能", "Choose items shown in Finder context menu"),
            symbol: "list.bullet.indent"
        ))
        let menuItems: [(String, String)] = [
            ("copyFolder", L10n.tr("复制当前目录路径", "Copy Folder Path")),
            ("copySelection", L10n.tr("复制所选文件路径", "Copy Selection Paths")),
            ("openTerminal", L10n.tr("在终端中打开", "Open in Terminal")),
            ("goUp", L10n.tr("进入上级目录", "Enclosing Folder")),
            ("newFile", L10n.tr("新建文件", "New File")),
        ]
        let checksStack = UIStyle.vStack(spacing: UIStyle.Metrics.sp2)
        for (index, item) in menuItems.enumerated() {
            let (key, title) = item
            let check = UIStyle.switchRow(title, target: self, action: #selector(toggleMenu(_:)))
            check.setAccessibilityLabel(title)
            check.setAccessibilityHelp(L10n.tr("控制 Finder 右键菜单中的此项目。", "Show or hide this item in the Finder context menu."))
            check.identifier = NSUserInterfaceItemIdentifier(key)
            menuChecks[key] = check
            checksStack.addArrangedSubview(check)
            UIStyle.fillWidth(check, in: checksStack)
            // 行间细线：把多行开关读成一个分组，而不是散落的勾选项
            if index < menuItems.count - 1 {
                let sep = UIStyle.hairline()
                checksStack.addArrangedSubview(sep)
                UIStyle.fillWidth(sep, in: checksStack)
            }
        }
        let menuCard = cardBox(containing: checksStack)
        stack.addArrangedSubview(menuCard)
        UIStyle.fillWidth(menuCard, in: stack)

        // ========== 菜单栏收纳 ==========
        stack.addArrangedSubview(sectionHeader(
            L10n.tr("菜单栏", "Menu Bar"),
            subtitle: L10n.tr("收纳被刘海遮挡的图标", "Hide overflow icons behind the notch"),
            symbol: "menubar.rectangle"
        ))
        let hiderPermissionCard = permissionStatusCard(
            name: L10n.tr("屏幕录制 / Screen Recording", "Screen Recording"),
            purpose: L10n.tr("用于识别被刘海或空间挤掉的菜单栏图标。", "Required to identify menu bar icons hidden by the notch or limited space."),
            granted: PermissionManager.isScreenCaptureTrusted,
            settingsKey: "screenCapture"
        )
        stack.addArrangedSubview(hiderPermissionCard)
        UIStyle.fillWidth(hiderPermissionCard, in: stack)

        let hiderInner = UIStyle.vStack(spacing: UIStyle.Metrics.sp8)
        hiderCheck = UIStyle.switchRow(
            L10n.tr("收纳菜单栏图标", "Collapse menu bar icons"),
            target: self, action: #selector(toggleHider)
        )
        hiderCheck.setAccessibilityHelp(L10n.tr("将溢出的菜单栏图标收纳到箭头菜单。", "Place overflow menu bar icons in the arrow menu."))
        hiderInner.addArrangedSubview(hiderCheck)
        hiderInner.addArrangedSubview(UIStyle.hint(
            L10n.tr("开启后菜单栏最右多出箭头「«」:顶部图标被刘海/空间挤掉时,点箭头查看并打开它们;首次需授权「屏幕录制」", "Adds « at the far right; when icons overflow the notch, click « to reveal them. Requires Screen Recording")
        ))
        let hiderCard = cardBox(containing: hiderInner)
        stack.addArrangedSubview(hiderCard)
        UIStyle.fillWidth(hiderCard, in: stack)
    }
}
