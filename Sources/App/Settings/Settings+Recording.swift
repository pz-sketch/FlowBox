import AppKit
import AVFoundation
import SharedCore
import Carbon.HIToolbox
import os

extension SettingsWindowController {
    func buildRecordingTab(tabView: NSTabView) {
        let stack = UIStyle.makeTab(tabView, identifier: "recording", label: L10n.tr("录屏", "Recording"))

        stack.addArrangedSubview(sectionHeader(
            L10n.tr("全屏录屏", "Screen Recording"),
            subtitle: L10n.tr("录制主显示器全屏画面 + 系统声音/麦克风,保存为桌面 .mov", "Record main display + system audio / mic, save .mov to Desktop"),
            symbol: "record.circle"
        ))

        let inner = UIStyle.vStack(spacing: UIStyle.Metrics.sp12)

        // 快捷键
        let hotkeyRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        hotkeyRow.addArrangedSubview(UIStyle.label(
            L10n.tr("录屏快捷键", "Recording Hotkey"),
            font: UIStyle.Text.body(), color: UIStyle.Palette.text
        ))
        recRecorder = HotKeyRecorder()
        recRecorder.setAccessibilityLabel(L10n.tr("录屏快捷键录制器", "Recording hotkey recorder"))
        recRecorder.font = UIStyle.Text.body()
        recRecorder.isBezeled = true
        recRecorder.bezelStyle = .roundedBezel
        recRecorder.isEditable = false
        recRecorder.alignment = .center
        recRecorder.placeholderString = L10n.tr("点击录制", "Click to record")
        recRecorder.onChange = { [weak self] code, mods in self?.applyRecHotKey(code: code, mods: mods) }
        hotkeyRow.addArrangedSubview(recRecorder)
        recRecorder.widthAnchor.constraint(equalToConstant: 120).isActive = true
        recHotKeyHint = UIStyle.label("", font: UIStyle.Text.caption(), color: UIStyle.Palette.danger)
        hotkeyRow.addArrangedSubview(recHotKeyHint)
        inner.addArrangedSubview(hotkeyRow)

        recSystemAudioCheck = UIStyle.checkbox(
            L10n.tr("录制系统声音(跟随画面)", "System audio (follow video)"),
            target: self, action: #selector(toggleRecSystemAudio)
        )
        inner.addArrangedSubview(recSystemAudioCheck)

        recMicCheck = UIStyle.checkbox(
            L10n.tr("录制麦克风", "Microphone"),
            target: self, action: #selector(toggleRecMic)
        )
        recMicCheck.setAccessibilityHelp(L10n.tr("将麦克风声音录入视频。", "Record microphone audio into the video."))
        inner.addArrangedSubview(recMicCheck)

        let sep = separatorView()
        inner.addArrangedSubview(sep)
        UIStyle.fillWidth(sep, in: inner)

        // 摄像头画中画
        recCameraCheck = UIStyle.checkbox(
            L10n.tr("叠加摄像头画中画(录进视频,可拖动)", "Camera PiP (burn into video, draggable)"),
            target: self, action: #selector(toggleRecCamera)
        )
        recCameraCheck.setAccessibilityHelp(L10n.tr("将可拖动的摄像头画中画合成到录屏中。", "Composite a draggable camera picture-in-picture into the recording."))
        inner.addArrangedSubview(recCameraCheck)

        let camRow = UIStyle.hStack(spacing: UIStyle.Metrics.sp8)
        camRow.addArrangedSubview(UIStyle.label(
            L10n.tr("画中画宽度", "PiP Width"),
            font: UIStyle.Text.caption(), color: UIStyle.Palette.textSecondary
        ))
        recCameraWidthSlider = NSSlider(value: 220, minValue: 120, maxValue: 360, target: self, action: #selector(cameraWidthChanged))
        recCameraWidthSlider.setAccessibilityLabel(L10n.tr("画中画宽度", "Picture-in-picture width"))
        recCameraWidthSlider.setAccessibilityHelp(L10n.tr("调整摄像头画中画宽度。", "Adjust the camera picture-in-picture width."))
        recCameraWidthSlider.controlSize = .small
        recCameraWidthSlider.translatesAutoresizingMaskIntoConstraints = false
        camRow.addArrangedSubview(recCameraWidthSlider)
        recCameraWidthSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
        recCameraWidthLabel = UIStyle.valueLabel("220")
        camRow.addArrangedSubview(recCameraWidthLabel)
        inner.addArrangedSubview(camRow)

        recCameraCircleCheck = UIStyle.checkbox(
            L10n.tr("圆形裁切", "Circular crop"),
            target: self, action: #selector(toggleCameraCircle)
        )
        inner.addArrangedSubview(recCameraCircleCheck)

        recCameraMirrorCheck = UIStyle.checkbox(
            L10n.tr("镜像(前置摄像头常用)", "Mirror (front camera)"),
            target: self, action: #selector(toggleCameraMirror)
        )
        inner.addArrangedSubview(recCameraMirrorCheck)

        inner.addArrangedSubview(UIStyle.hint(
            L10n.tr("录制时会弹出可拖动的摄像头预览,拖到想要的位置后开始录/录制中也可拖,位置会自动记忆,合成进最终 .mov。首次需授权「摄像头」。", "A draggable camera preview appears before/during recording; position is remembered and composited into final .mov. Requires Camera permission."),
            color: UIStyle.Palette.textSecondary.withAlphaComponent(0.85), maxWidth: 460, lines: 2
        ))
        inner.addArrangedSubview(UIStyle.hint(
            L10n.tr("全屏 + 带声:默认带麦克风;若无需人声可关掉麦克风。", "Fullscreen + audio: mic on by default; turn off if you don't need voice."),
            color: UIStyle.Palette.textSecondary.withAlphaComponent(0.85), maxWidth: 460, lines: 2
        ))

        let permissionsCard = permissionSummaryCard([
            (L10n.tr("屏幕录制", "Screen Recording"), PermissionManager.isScreenCaptureTrusted, "screenCapture"),
            (L10n.tr("摄像头", "Camera"), AVCaptureDevice.authorizationStatus(for: .video) == .authorized, "camera"),
            (L10n.tr("麦克风", "Microphone"), AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, "microphone")
        ])
        stack.addArrangedSubview(permissionsCard)
        UIStyle.fillWidth(permissionsCard, in: stack)

        let recCard = cardBox(containing: inner)
        stack.addArrangedSubview(recCard)
        UIStyle.fillWidth(recCard, in: stack)

        stack.addArrangedSubview(UIStyle.hint(
            L10n.tr("点击菜单栏「录屏」或按快捷键开始(3秒倒计时) → 顶部悬浮条显示时长 → 点停止保存到桌面。首次需授权「屏幕录制」/「麦克风」。", "Click menu bar Recording or hotkey to start (3s countdown) → top bar shows time → Stop to save to Desktop. Requires Screen Recording / Microphone."),
            color: UIStyle.Palette.textSecondary.withAlphaComponent(0.78), maxWidth: 460, lines: 2
        ))
        stack.addArrangedSubview(UIStyle.hint(
            L10n.tr("录屏转 GIF:菜单栏 →「录屏转 GIF…」,选 .mov/mp4 后可调帧率(5~15)与最大宽度,GIF 输出到视频同目录。", "Recording → GIF: menu bar → \"Recording → GIF…\", pick a .mov/mp4, adjust frame rate (5–15) and max width; the GIF is saved next to the video."),
            color: UIStyle.Palette.textSecondary.withAlphaComponent(0.78), maxWidth: 460, lines: 2
        ))
    }
}
