import AppKit
import AVFoundation
import SharedCore
import Carbon.HIToolbox
import os

extension SettingsWindowController {
    func buildMouseTab(tabView: NSTabView) {
                // ========== Tab 2: 鼠标 ==========
                let mouseTab = NSTabViewItem(identifier: "mouse")
                mouseTab.label = L10n.tr("鼠标", "Mouse")
                let mouseView = NSView()
                let mouseStackOuter = NSStackView()
                mouseStackOuter.orientation = .vertical
                mouseStackOuter.alignment = .leading
                mouseStackOuter.spacing = 18
                mouseStackOuter.translatesAutoresizingMaskIntoConstraints = false
                mouseView.addSubview(mouseStackOuter)
                NSLayoutConstraint.activate([
                    mouseStackOuter.leadingAnchor.constraint(equalTo: mouseView.leadingAnchor, constant: 20),
                    mouseStackOuter.trailingAnchor.constraint(equalTo: mouseView.trailingAnchor, constant: -20),
                    mouseStackOuter.topAnchor.constraint(equalTo: mouseView.topAnchor, constant: 18),
                    mouseStackOuter.bottomAnchor.constraint(lessThanOrEqualTo: mouseView.bottomAnchor, constant: -8),
                ])

                mouseStackOuter.addArrangedSubview(sectionHeader(L10n.tr("鼠标", "Mouse"), subtitle: L10n.tr("滚轮方向与平滑滚动(类似 Mos)", "Wheel direction & smooth scrolling (like Mos)"), symbol: "computermouse"))
                let accessibilityCard = permissionStatusCard(
                    name: L10n.tr("辅助功能 / Accessibility", "Accessibility"),
                    purpose: L10n.tr("用于拦截外接鼠标滚轮事件，触控板不受影响。", "Required to intercept external mouse wheel events; trackpad is unaffected."),
                    granted: PermissionManager.isEffectivelyTrusted,
                    settingsKey: "accessibility"
                )
                mouseStackOuter.addArrangedSubview(accessibilityCard)
                accessibilityCard.widthAnchor.constraint(equalTo: mouseStackOuter.widthAnchor).isActive = true
                let mouseInner = NSStackView()
                mouseInner.orientation = .vertical
                mouseInner.alignment = .leading
                mouseInner.spacing = 12

                let reverseRow = NSStackView()
                reverseRow.orientation = .vertical
                reverseRow.alignment = .leading
                reverseRow.spacing = 4
                reverseCheck = NSButton(checkboxWithTitle: L10n.tr("反转外接鼠标滚轮方向", "Reverse external mouse wheel"), target: self, action: #selector(toggleReverse))
                reverseCheck.setAccessibilityHelp(L10n.tr("反转外接鼠标的垂直滚轮方向。", "Reverse the vertical scroll direction of external mice."))
                reverseRow.addArrangedSubview(reverseCheck)
                let reverseHint = NSTextField(labelWithString: L10n.tr("触控板不受影响;首次开启需要在系统设置里授权「辅助功能」", "Trackpad unaffected; grant Accessibility on first enable"))
                reverseHint.font = .systemFont(ofSize: 11, weight: .regular)
                reverseHint.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.85)
                reverseRow.addArrangedSubview(reverseHint)
                mouseInner.addArrangedSubview(reverseRow)

                mouseInner.addArrangedSubview(separatorView())

                let smoothStack = NSStackView()
                smoothStack.orientation = .vertical
                smoothStack.alignment = .leading
                smoothStack.spacing = 6
                smoothCheck = NSButton(checkboxWithTitle: L10n.tr("启用流畅滚动", "Enable smooth scrolling"), target: self, action: #selector(toggleSmooth))
                smoothCheck.setAccessibilityHelp(L10n.tr("把离散滚动转换为平滑惯性滚动。", "Convert discrete scrolling into smooth momentum scrolling."))
                smoothStack.addArrangedSubview(smoothCheck)

                let stepRow = NSStackView()
                stepRow.orientation = .horizontal
                stepRow.alignment = .centerY
                stepRow.spacing = 8
                let stepLabel = NSTextField(labelWithString: L10n.tr("最短步长", "Min Step"))
                stepLabel.font = .systemFont(ofSize: 11, weight: .medium)
                stepLabel.textColor = NSColor.secondaryLabelColor
                stepRow.addArrangedSubview(stepLabel)

                stepSlider = NSSlider(value: config.scroll.minStep, minValue: 5, maxValue: 300, target: self, action: #selector(stepSliderChanged))
                stepSlider.controlSize = .small
                stepSlider.frame = NSRect(x: 0, y: 0, width: 180, height: 20)
                stepSlider.translatesAutoresizingMaskIntoConstraints = false
                stepRow.addArrangedSubview(stepSlider)
                NSLayoutConstraint.activate([ stepSlider.widthAnchor.constraint(equalToConstant: 160) ])

                stepField = NSTextField(string: String(format: "%.0f", config.scroll.minStep))
                stepField.setAccessibilityLabel(L10n.tr("最短滚动步长数值", "Minimum scroll step value"))
                stepField.setAccessibilityHelp(L10n.tr("输入 5 到 300 之间的数值。", "Enter a value from 5 to 300."))
                stepField.target = self
                stepField.action = #selector(stepFieldChanged)
                stepField.alignment = .right
                stepField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                stepField.translatesAutoresizingMaskIntoConstraints = false
                stepRow.addArrangedSubview(stepField)
                NSLayoutConstraint.activate([ stepField.widthAnchor.constraint(equalToConstant: 56) ])

                let stepStepper = NSStepper()
                stepStepper.minValue = 5
                stepStepper.maxValue = 300
                stepStepper.increment = 5
                stepStepper.valueWraps = false
                stepStepper.doubleValue = config.scroll.minStep
                stepStepper.target = self
                stepStepper.action = #selector(stepStepperChanged)
                stepRow.addArrangedSubview(stepStepper)

                let smoothHint = NSTextField(labelWithString: L10n.tr("把鼠标的离散滚动变成触控板般的平滑惯性滑动;最短步长控制单次滚动的距离", "Turn discrete ticks into trackpad-like momentum; Min Step controls distance per scroll"))
                smoothHint.font = .systemFont(ofSize: 11, weight: .regular)
                smoothHint.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.85)
                smoothStack.addArrangedSubview(stepRow)
                smoothStack.addArrangedSubview(smoothHint)
                mouseInner.addArrangedSubview(smoothStack)

                let mouseCard = cardBox(containing: mouseInner)
                mouseStackOuter.addArrangedSubview(mouseCard)
                mouseCard.widthAnchor.constraint(equalTo: mouseStackOuter.widthAnchor).isActive = true

                mouseTab.view = mouseView
                tabView.addTabViewItem(mouseTab)

    }
}
