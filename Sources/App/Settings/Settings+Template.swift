import AppKit
import AVFoundation
import SharedCore
import Carbon.HIToolbox
import os

extension SettingsWindowController {
    func buildTemplateTab(tabView: NSTabView) {
        let stack = UIStyle.makeTab(tabView, identifier: "template", label: L10n.tr("模板", "Templates"), spacing: UIStyle.Metrics.sp14)

        stack.addArrangedSubview(sectionHeader(
            L10n.tr("新建文件模板", "New File Templates"),
            subtitle: L10n.tr("勾选的会出现在「新建文件」子菜单", "Checked items appear in the New File submenu"),
            symbol: "doc.badge.plus"
        ))

        listStack = UIStyle.vStack(spacing: UIStyle.Metrics.sp4)
        listStack.edgeInsets = NSEdgeInsets(
            top: UIStyle.Metrics.sp8, left: UIStyle.Metrics.sp8,
            bottom: UIStyle.Metrics.sp8, right: UIStyle.Metrics.sp8
        )

        // 列表自然撑开、一屏全部展示(用户指定不滚动);模板特别多时由页面级滚动兜底
        let listCard = UIStyle.card(listStack, padding: 0)
        stack.addArrangedSubview(listCard)
        UIStyle.fillWidth(listCard, in: stack)

        let buttons = UIStyle.hStack(spacing: UIStyle.Metrics.sp10)
        let add = UIStyle.primaryButton(
            L10n.tr("添加模板", "Add Template"), symbol: "plus",
            target: self, action: #selector(addTemplate)
        )
        add.setAccessibilityLabel(L10n.tr("添加模板", "Add template"))
        add.toolTip = L10n.tr("添加一个新建文件模板", "Add a new file template")
        buttons.addArrangedSubview(add)

        let reset = UIStyle.secondaryButton(
            L10n.tr("恢复默认", "Restore Defaults"),
            target: self, action: #selector(resetTemplates)
        )
        reset.setAccessibilityLabel(L10n.tr("恢复默认模板", "Restore default templates"))
        reset.toolTip = L10n.tr("仅恢复模板设置，不影响其他选项", "Restore templates only; keep other settings")
        buttons.addArrangedSubview(reset)

        stack.addArrangedSubview(buttons)
    }
}
