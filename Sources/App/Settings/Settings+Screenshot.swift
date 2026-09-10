import AppKit
import AVFoundation
import SharedCore
import Carbon.HIToolbox
import os

extension SettingsWindowController {
    func buildScreenshotTab(tabView: NSTabView) {
        let stack = UIStyle.makeTab(tabView, identifier: "screenshot", label: L10n.tr("截图", "Screenshot"))

        stack.addArrangedSubview(sectionHeader(
            L10n.tr("框选截图", "Area Screenshot"),
            subtitle: L10n.tr("类似 Snipaste 的简化版:快捷键冻结屏幕 → 框选 → 画笔 / 马赛克 → 复制", "Snipaste-like: hotkey to freeze → select → annotate → copy"),
            symbol: "camera.viewfinder"
        ))

        let screenCard = permissionStatusCard(
            name: L10n.tr("屏幕录制 / Screen Recording", "Screen Recording"),
            purpose: L10n.tr("用于冻结屏幕并读取截图内容。", "Required to freeze the screen and read screenshot content."),
            granted: PermissionManager.isScreenCaptureTrusted,
            settingsKey: "screenCapture"
        )
        stack.addArrangedSubview(screenCard)
        UIStyle.fillWidth(screenCard, in: stack)

        let inner = UIStyle.vStack(spacing: UIStyle.Metrics.sp12)

        // 快捷键录制
        let hotkeyRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        hotkeyRow.addArrangedSubview(UIStyle.label(
            L10n.tr("截图快捷键", "Screenshot Hotkey"),
            font: UIStyle.Text.body(.medium), color: UIStyle.Palette.text
        ))
        shotRecorder = HotKeyRecorder()
        shotRecorder.setAccessibilityLabel(L10n.tr("截图快捷键录制器", "Screenshot hotkey recorder"))
        shotRecorder.font = UIStyle.Text.body()
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
        shotHotKeyHint = UIStyle.label("", font: UIStyle.Text.caption(), color: UIStyle.Palette.danger)
        hotkeyRow.addArrangedSubview(shotHotKeyHint)
        inner.addArrangedSubview(hotkeyRow)

        // 画笔颜色
        let colorRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        colorRow.addArrangedSubview(UIStyle.label(
            L10n.tr("画笔颜色", "Pen Color"),
            font: UIStyle.Text.body(.medium), color: UIStyle.Palette.text
        ))
        penWell = NSColorWell(frame: NSRect(x: 0, y: 0, width: 44, height: 22))
        penWell.setAccessibilityLabel(L10n.tr("画笔颜色", "Pen color"))
        penWell.setAccessibilityHelp(L10n.tr("选择截图标注画笔的颜色。", "Choose the color used by the screenshot annotation pen."))
        penWell.wantsLayer = true
        penWell.layer?.cornerRadius = UIStyle.Metrics.radiusS
        penWell.layer?.masksToBounds = true
        penWell.target = self
        penWell.action = #selector(penColorChanged)
        colorRow.addArrangedSubview(penWell)
        colorRow.addArrangedSubview(UIStyle.hint(
            L10n.tr("自由画笔标注用;马赛克笔刷宽度为画笔的 3 倍", "Pen for annotation; mosaic brush is 3× pen width"),
            color: UIStyle.Palette.textSecondary.withAlphaComponent(0.85), lines: 1
        ))
        inner.addArrangedSubview(colorRow)

        // 笔宽
        let penRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        penRow.addArrangedSubview(UIStyle.label(
            L10n.tr("画笔宽度", "Pen Width"),
            font: UIStyle.Text.body(.medium), color: UIStyle.Palette.text
        ))
        penSlider = NSSlider(value: config.screenshot.penWidth, minValue: 2, maxValue: 14, target: self, action: #selector(penWidthChanged))
        penSlider.setAccessibilityLabel(L10n.tr("画笔宽度", "Pen width"))
        penSlider.setAccessibilityHelp(L10n.tr("调整截图标注画笔宽度。", "Adjust the screenshot annotation pen width."))
        penSlider.controlSize = .small
        penSlider.translatesAutoresizingMaskIntoConstraints = false
        penRow.addArrangedSubview(penSlider)
        penSlider.widthAnchor.constraint(equalToConstant: 140).isActive = true
        penValueLabel = UIStyle.valueLabel()
        penRow.addArrangedSubview(penValueLabel)
        inner.addArrangedSubview(penRow)

        // 马赛克粒度
        let mosaicRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        mosaicRow.addArrangedSubview(UIStyle.label(
            L10n.tr("马赛克粒度", "Mosaic Size"),
            font: UIStyle.Text.body(.medium), color: UIStyle.Palette.text
        ))
        mosaicSlider = NSSlider(value: config.screenshot.mosaicBlock, minValue: 6, maxValue: 40, target: self, action: #selector(mosaicChanged))
        mosaicSlider.setAccessibilityLabel(L10n.tr("马赛克粒度", "Mosaic size"))
        mosaicSlider.setAccessibilityHelp(L10n.tr("调整马赛克方块大小。", "Adjust the mosaic block size."))
        mosaicSlider.controlSize = .small
        mosaicSlider.translatesAutoresizingMaskIntoConstraints = false
        mosaicRow.addArrangedSubview(mosaicSlider)
        mosaicSlider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        mosaicValueLabel = UIStyle.valueLabel()
        mosaicRow.addArrangedSubview(mosaicValueLabel)
        inner.addArrangedSubview(mosaicRow)

        let shotCard = cardBox(containing: inner)
        stack.addArrangedSubview(shotCard)
        UIStyle.fillWidth(shotCard, in: stack)

        stack.addArrangedSubview(UIStyle.hint(
            L10n.tr("框选后松开鼠标出现工具条:画笔 / 马赛克 / 文字 / 撤销 / 保存;Enter 或「复制」把选区存入剪贴板,Esc 取消,⌘S 保存到桌面。文字工具在选区内点击后输入,Enter 确认。首次使用需授权「屏幕录制」。", "Release to show toolbar: pen / mosaic / text / undo / save; Enter or Copy to clipboard, Esc to cancel, ⌘S to save. Click inside selection to type text. Requires Screen Recording permission."),
            maxWidth: 460, lines: 2
        ))
    }
}
