import AppKit
import AVFoundation
import SharedCore
import Carbon.HIToolbox
import os

extension SettingsWindowController {
    func buildMenuTab(tabView: NSTabView) {
                // ========== Tab 1: 菜单 ==========
                let menuTab = NSTabViewItem(identifier: "menu")
                menuTab.label = L10n.tr("菜单", "Menu")
                let menuView = NSView()
                // 用滚动-free 的栈,内容少无需滚动
                let menuStack = NSStackView()
                menuStack.orientation = .vertical
                menuStack.alignment = .leading
                menuStack.spacing = 18
                menuStack.translatesAutoresizingMaskIntoConstraints = false
                menuView.addSubview(menuStack)
                NSLayoutConstraint.activate([
                    menuStack.leadingAnchor.constraint(equalTo: menuView.leadingAnchor, constant: 20),
                    menuStack.trailingAnchor.constraint(equalTo: menuView.trailingAnchor, constant: -20),
                    menuStack.topAnchor.constraint(equalTo: menuView.topAnchor, constant: 18),
                    menuStack.bottomAnchor.constraint(lessThanOrEqualTo: menuView.bottomAnchor, constant: -8),
                ])

                menuStack.addArrangedSubview(sectionHeader(L10n.tr("菜单", "Menu"), subtitle: L10n.tr("选择要在 Finder 右键中显示的功能", "Choose items shown in Finder context menu"), symbol: "list.bullet.indent"))
                let menuItems: [(String, String)] = [
                    ("copyFolder", L10n.tr("复制当前目录路径", "Copy Folder Path")),
                    ("copySelection", L10n.tr("复制所选文件路径", "Copy Selection Paths")),
                    ("openTerminal", L10n.tr("在终端中打开", "Open in Terminal")),
                    ("newFile", L10n.tr("新建文件", "New File")),
                ]
                let checksStack = NSStackView()
                checksStack.orientation = .vertical
                checksStack.alignment = .leading
                checksStack.spacing = 10
                for (key, title) in menuItems {
                    let check = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggleMenu(_:)))
                    check.setAccessibilityLabel(title)
                    check.setAccessibilityHelp(L10n.tr("控制 Finder 右键菜单中的此项目。", "Show or hide this item in the Finder context menu."))
                    check.identifier = NSUserInterfaceItemIdentifier(key)
                    menuChecks[key] = check
                    checksStack.addArrangedSubview(check)
                }
                let menuCard = cardBox(containing: checksStack)
                menuStack.addArrangedSubview(menuCard)
                menuCard.widthAnchor.constraint(equalTo: menuStack.widthAnchor).isActive = true

                menuStack.addArrangedSubview(sectionHeader(L10n.tr("菜单栏", "Menu Bar"), subtitle: L10n.tr("收纳被刘海遮挡的图标", "Hide overflow icons behind the notch"), symbol: "menubar.rectangle"))
                let hiderPermissionCard = permissionStatusCard(
                    name: L10n.tr("屏幕录制 / Screen Recording", "Screen Recording"),
                    purpose: L10n.tr("用于识别被刘海或空间挤掉的菜单栏图标。", "Required to identify menu bar icons hidden by the notch or limited space."),
                    granted: PermissionManager.isScreenCaptureTrusted,
                    settingsKey: "screenCapture"
                )
                menuStack.addArrangedSubview(hiderPermissionCard)
                hiderPermissionCard.widthAnchor.constraint(equalTo: menuStack.widthAnchor).isActive = true
                let hiderInner = NSStackView()
                hiderInner.orientation = .vertical
                hiderInner.alignment = .leading
                hiderInner.spacing = 8
                hiderCheck = NSButton(checkboxWithTitle: L10n.tr("收纳菜单栏图标", "Collapse menu bar icons"), target: self, action: #selector(toggleHider))
                hiderCheck.setAccessibilityHelp(L10n.tr("将溢出的菜单栏图标收纳到箭头菜单。", "Place overflow menu bar icons in the arrow menu."))
                hiderInner.addArrangedSubview(hiderCheck)
                let hiderHint = NSTextField(labelWithString: L10n.tr("开启后菜单栏最右多出箭头「«」:顶部图标被刘海/空间挤掉时,点箭头查看并打开它们;首次需授权「屏幕录制」", "Adds « at the far right; when icons overflow the notch, click « to reveal them. Requires Screen Recording"))
                hiderHint.font = .systemFont(ofSize: 11, weight: .regular)
                hiderHint.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.9)
                hiderHint.lineBreakMode = .byWordWrapping
                hiderHint.maximumNumberOfLines = 2
                hiderHint.preferredMaxLayoutWidth = 460
                hiderInner.addArrangedSubview(hiderHint)
                let hiderCard = cardBox(containing: hiderInner)
                menuStack.addArrangedSubview(hiderCard)
                hiderCard.widthAnchor.constraint(equalTo: menuStack.widthAnchor).isActive = true


                menuTab.view = menuView
                tabView.addTabViewItem(menuTab)

    }
}
