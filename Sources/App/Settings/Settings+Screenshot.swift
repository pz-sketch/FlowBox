import AppKit
import AVFoundation
import SharedCore
import Carbon.HIToolbox
import os

extension SettingsWindowController {
    func buildScreenshotTab(tabView: NSTabView) {
                // ========== Tab 4: 截图 ==========
                let shotTab = NSTabViewItem(identifier: "screenshot")
                shotTab.label = L10n.tr("截图", "Screenshot")
                let shotView = NSView()
                let shotStack = NSStackView()
                shotStack.orientation = .vertical
                shotStack.alignment = .leading
                shotStack.spacing = 18
                shotStack.translatesAutoresizingMaskIntoConstraints = false
                shotView.addSubview(shotStack)
                NSLayoutConstraint.activate([
                    shotStack.leadingAnchor.constraint(equalTo: shotView.leadingAnchor, constant: 20),
                    shotStack.trailingAnchor.constraint(equalTo: shotView.trailingAnchor, constant: -20),
                    shotStack.topAnchor.constraint(equalTo: shotView.topAnchor, constant: 18),
                    shotStack.bottomAnchor.constraint(lessThanOrEqualTo: shotView.bottomAnchor, constant: -8),
                ])

                shotStack.addArrangedSubview(
                    sectionHeader(
                        L10n.tr("框选截图", "Area Screenshot"),
                        subtitle: L10n.tr("类似 Snipaste 的简化版:快捷键冻结屏幕 → 框选 → 画笔 / 马赛克 → 复制", "Snipaste-like: hotkey to freeze → select → annotate → copy"),
                        symbol: "camera.viewfinder"
                    )
                )

                let screenCard = permissionStatusCard(
                    name: L10n.tr("屏幕录制 / Screen Recording", "Screen Recording"),
                    purpose: L10n.tr("用于冻结屏幕并读取截图内容。", "Required to freeze the screen and read screenshot content."),
                    granted: PermissionManager.isScreenCaptureTrusted,
                    settingsKey: "screenCapture"
                )
                shotStack.addArrangedSubview(screenCard)
                screenCard.widthAnchor.constraint(equalTo: shotStack.widthAnchor).isActive = true

                let shotInner = NSStackView()
                shotInner.orientation = .vertical
                shotInner.alignment = .leading
                shotInner.spacing = 12

                // 快捷键录制
                let hotkeyRow = NSStackView()
                hotkeyRow.orientation = .horizontal
                hotkeyRow.alignment = .centerY
                hotkeyRow.spacing = 8
                let hkLabel = NSTextField(labelWithString: L10n.tr("截图快捷键", "Screenshot Hotkey"))
                hkLabel.font = .systemFont(ofSize: 12, weight: .medium)
                hotkeyRow.addArrangedSubview(hkLabel)
                shotRecorder = HotKeyRecorder()
                shotRecorder.setAccessibilityLabel(L10n.tr("截图快捷键录制器", "Screenshot hotkey recorder"))
                shotRecorder.font = .systemFont(ofSize: 12)
                shotRecorder.isBezeled = true
                shotRecorder.bezelStyle = .roundedBezel
                shotRecorder.isEditable = false
                shotRecorder.alignment = .center
                shotRecorder.placeholderString = L10n.tr("点击录制", "Click to record")
                shotRecorder.onChange = { [weak self] code, mods in
                    self?.applyHotKey(code: code, mods: mods)
                }
                hotkeyRow.addArrangedSubview(shotRecorder)
                shotRecorder.widthAnchor.constraint(equalToConstant: 120).isActive = true
                shotHotKeyHint = NSTextField(labelWithString: "")
                shotHotKeyHint.font = .systemFont(ofSize: 11)
                shotHotKeyHint.textColor = .systemRed
                hotkeyRow.addArrangedSubview(shotHotKeyHint)
                shotInner.addArrangedSubview(hotkeyRow)

                // 画笔颜色
                let colorRow = NSStackView()
                colorRow.orientation = .horizontal
                colorRow.alignment = .centerY
                colorRow.spacing = 8
                let colorLabel = NSTextField(labelWithString: L10n.tr("画笔颜色", "Pen Color"))
                colorLabel.font = .systemFont(ofSize: 12, weight: .medium)
                colorRow.addArrangedSubview(colorLabel)
                penWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 22))
                penWell.setAccessibilityLabel(L10n.tr("画笔颜色", "Pen color"))
                penWell.setAccessibilityHelp(L10n.tr("选择截图标注画笔的颜色。", "Choose the color used by the screenshot annotation pen."))
                penWell.wantsLayer = true
                penWell.layer?.cornerRadius = 6
                penWell.layer?.masksToBounds = true
                penWell.target = self
                penWell.action = #selector(penColorChanged)
                colorRow.addArrangedSubview(penWell)
                let colorHint = NSTextField(labelWithString: L10n.tr("自由画笔标注用;马赛克笔刷宽度为画笔的 3 倍", "Pen for annotation; mosaic brush is 3× pen width"))
                colorHint.font = .systemFont(ofSize: 11)
                colorHint.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.85)
                colorRow.addArrangedSubview(colorHint)
                shotInner.addArrangedSubview(colorRow)

                // 笔宽
                let penRow = NSStackView()
                penRow.orientation = .horizontal
                penRow.alignment = .centerY
                penRow.spacing = 8
                let penLabel = NSTextField(labelWithString: L10n.tr("画笔宽度", "Pen Width"))
                penLabel.font = .systemFont(ofSize: 12, weight: .medium)
                penRow.addArrangedSubview(penLabel)
                penSlider = NSSlider(value: config.screenshot.penWidth, minValue: 2, maxValue: 14, target: self, action: #selector(penWidthChanged))
                penSlider.setAccessibilityLabel(L10n.tr("画笔宽度", "Pen width"))
                penSlider.setAccessibilityHelp(L10n.tr("调整截图标注画笔宽度。", "Adjust the screenshot annotation pen width."))
                penSlider.controlSize = .small
                penSlider.translatesAutoresizingMaskIntoConstraints = false
                penRow.addArrangedSubview(penSlider)
                NSLayoutConstraint.activate([ penSlider.widthAnchor.constraint(equalToConstant: 140) ])
                penValueLabel = NSTextField(labelWithString: "")
                penValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                penValueLabel.textColor = .secondaryLabelColor
                penRow.addArrangedSubview(penValueLabel)
                shotInner.addArrangedSubview(penRow)

                // 马赛克粒度
                let mosaicRow = NSStackView()
                mosaicRow.orientation = .horizontal
                mosaicRow.alignment = .centerY
                mosaicRow.spacing = 8
                let mosaicLabel = NSTextField(labelWithString: L10n.tr("马赛克粒度", "Mosaic Size"))
                mosaicLabel.font = .systemFont(ofSize: 12, weight: .medium)
                mosaicRow.addArrangedSubview(mosaicLabel)
                mosaicSlider = NSSlider(value: config.screenshot.mosaicBlock, minValue: 6, maxValue: 40, target: self, action: #selector(mosaicChanged))
                mosaicSlider.setAccessibilityLabel(L10n.tr("马赛克粒度", "Mosaic size"))
                mosaicSlider.setAccessibilityHelp(L10n.tr("调整马赛克方块大小。", "Adjust the mosaic block size."))
                mosaicSlider.controlSize = .small
                mosaicSlider.translatesAutoresizingMaskIntoConstraints = false
                mosaicRow.addArrangedSubview(mosaicSlider)
                NSLayoutConstraint.activate([ mosaicSlider.widthAnchor.constraint(equalToConstant: 150) ])
                mosaicValueLabel = NSTextField(labelWithString: "")
                mosaicValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                mosaicValueLabel.textColor = .secondaryLabelColor
                mosaicRow.addArrangedSubview(mosaicValueLabel)
                shotInner.addArrangedSubview(mosaicRow)

                let shotCard = cardBox(containing: shotInner)
                shotStack.addArrangedSubview(shotCard)
                shotCard.widthAnchor.constraint(equalTo: shotStack.widthAnchor).isActive = true

                let shotHint = NSTextField(labelWithString: L10n.tr("框选后松开鼠标出现工具条:画笔 / 马赛克 / 文字 / 撤销 / 保存;Enter 或「复制」把选区存入剪贴板,Esc 取消,⌘S 保存到桌面。文字工具在选区内点击后输入,Enter 确认。首次使用需授权「屏幕录制」。", "Release to show toolbar: pen / mosaic / text / undo / save; Enter or Copy to clipboard, Esc to cancel, ⌘S to save. Click inside selection to type text. Requires Screen Recording permission."))
                shotHint.font = .systemFont(ofSize: 11)
                shotHint.textColor = .secondaryLabelColor
                shotHint.lineBreakMode = .byWordWrapping
                shotHint.maximumNumberOfLines = 2
                shotHint.preferredMaxLayoutWidth = 460
                shotStack.addArrangedSubview(shotHint)

                shotTab.view = shotView
                tabView.addTabViewItem(shotTab)

    }
}
