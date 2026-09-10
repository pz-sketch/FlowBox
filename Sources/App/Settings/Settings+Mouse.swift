import AppKit
import AVFoundation
import SharedCore
import Carbon.HIToolbox
import os

extension SettingsWindowController {
    func buildMouseTab(tabView: NSTabView) {
        let stack = UIStyle.makeTab(tabView, identifier: "mouse", label: L10n.tr("鼠标", "Mouse"))

        stack.addArrangedSubview(sectionHeader(
            L10n.tr("鼠标", "Mouse"),
            subtitle: L10n.tr("滚轮方向与平滑滚动(类似 Mos)", "Wheel direction & smooth scrolling (like Mos)"),
            symbol: "computermouse"
        ))
        let accessibilityCard = permissionStatusCard(
            name: L10n.tr("辅助功能 / Accessibility", "Accessibility"),
            purpose: L10n.tr("用于拦截外接鼠标滚轮事件，触控板不受影响。", "Required to intercept external mouse wheel events; trackpad is unaffected."),
            granted: PermissionManager.isEffectivelyTrusted,
            settingsKey: "accessibility"
        )
        stack.addArrangedSubview(accessibilityCard)
        UIStyle.fillWidth(accessibilityCard, in: stack)

        let inner = UIStyle.vStack(spacing: UIStyle.Metrics.sp12)

        // 反转滚轮
        let reverseRow = UIStyle.vStack(spacing: UIStyle.Metrics.sp4)
        reverseCheck = UIStyle.checkbox(
            L10n.tr("反转外接鼠标滚轮方向", "Reverse external mouse wheel"),
            target: self, action: #selector(toggleReverse)
        )
        reverseCheck.setAccessibilityHelp(L10n.tr("反转外接鼠标的垂直滚轮方向。", "Reverse the vertical scroll direction of external mice."))
        reverseRow.addArrangedSubview(reverseCheck)
        reverseRow.addArrangedSubview(UIStyle.hint(
            L10n.tr("触控板不受影响;首次开启需要在系统设置里授权「辅助功能」", "Trackpad unaffected; grant Accessibility on first enable"),
            color: UIStyle.Palette.textSecondary.withAlphaComponent(0.85), lines: 2
        ))
        inner.addArrangedSubview(reverseRow)

        let sep = separatorView()
        inner.addArrangedSubview(sep)
        UIStyle.fillWidth(sep, in: inner)

        // 平滑滚动
        let smoothStack = UIStyle.vStack(spacing: UIStyle.Metrics.sp6)
        smoothCheck = UIStyle.checkbox(
            L10n.tr("启用流畅滚动", "Enable smooth scrolling"),
            target: self, action: #selector(toggleSmooth)
        )
        smoothCheck.setAccessibilityHelp(L10n.tr("把离散滚动转换为平滑惯性滚动。", "Convert discrete scrolling into smooth momentum scrolling."))
        smoothStack.addArrangedSubview(smoothCheck)

        let stepRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        stepRow.addArrangedSubview(UIStyle.label(
            L10n.tr("最短步长", "Min Step"),
            font: UIStyle.Text.caption(.medium), color: UIStyle.Palette.textSecondary
        ))

        stepSlider = NSSlider(value: config.scroll.minStep, minValue: 5, maxValue: 300, target: self, action: #selector(stepSliderChanged))
        stepSlider.controlSize = .small
        stepSlider.translatesAutoresizingMaskIntoConstraints = false
        stepRow.addArrangedSubview(stepSlider)
        stepSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true

        stepField = NSTextField(string: String(format: "%.0f", config.scroll.minStep))
        stepField.setAccessibilityLabel(L10n.tr("最短滚动步长数值", "Minimum scroll step value"))
        stepField.setAccessibilityHelp(L10n.tr("输入 5 到 300 之间的数值。", "Enter a value from 5 to 300."))
        stepField.target = self
        stepField.action = #selector(stepFieldChanged)
        stepField.alignment = .right
        stepField.font = UIStyle.Text.monoDigit(12)
        stepField.translatesAutoresizingMaskIntoConstraints = false
        stepRow.addArrangedSubview(stepField)
        stepField.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let stepStepper = NSStepper()
        stepStepper.minValue = 5
        stepStepper.maxValue = 300
        stepStepper.increment = 5
        stepStepper.valueWraps = false
        stepStepper.doubleValue = config.scroll.minStep
        stepStepper.target = self
        stepStepper.action = #selector(stepStepperChanged)
        stepRow.addArrangedSubview(stepStepper)

        smoothStack.addArrangedSubview(stepRow)
        smoothStack.addArrangedSubview(UIStyle.hint(
            L10n.tr("把鼠标的离散滚动变成触控板般的平滑惯性滑动;最短步长控制单次滚动的距离", "Turn discrete ticks into trackpad-like momentum; Min Step controls distance per scroll"),
            color: UIStyle.Palette.textSecondary.withAlphaComponent(0.85), lines: 2
        ))
        inner.addArrangedSubview(smoothStack)

        let mouseCard = cardBox(containing: inner)
        stack.addArrangedSubview(mouseCard)
        UIStyle.fillWidth(mouseCard, in: stack)
    }
}
