import AppKit
import AVFoundation
import SharedCore
import Carbon.HIToolbox
import os

extension SettingsWindowController {
    func buildRecordingTab(tabView: NSTabView) {
                // ========== Tab 5: 录屏 ==========
                let recTab = NSTabViewItem(identifier: "recording")
                recTab.label = L10n.tr("录屏", "Recording")
                let recView = NSView()
                let recStack = NSStackView()
                recStack.orientation = .vertical
                recStack.alignment = .leading
                recStack.spacing = 18
                recStack.translatesAutoresizingMaskIntoConstraints = false
                recView.addSubview(recStack)
                NSLayoutConstraint.activate([
                    recStack.leadingAnchor.constraint(equalTo: recView.leadingAnchor, constant: 20),
                    recStack.trailingAnchor.constraint(equalTo: recView.trailingAnchor, constant: -20),
                    recStack.topAnchor.constraint(equalTo: recView.topAnchor, constant: 18),
                    recStack.bottomAnchor.constraint(lessThanOrEqualTo: recView.bottomAnchor, constant: -8),
                ])
                recStack.addArrangedSubview(
                    sectionHeader(L10n.tr("全屏录屏", "Screen Recording"), subtitle: L10n.tr("录制主显示器全屏画面 + 系统声音/麦克风,保存为桌面 .mov", "Record main display + system audio / mic, save .mov to Desktop"), symbol: "record.circle")
                )
                let recInner = NSStackView()
                recInner.orientation = .vertical
                recInner.alignment = .leading
                recInner.spacing = 12
                let recHotkeyRow = NSStackView()
                recHotkeyRow.orientation = .horizontal
                recHotkeyRow.alignment = .centerY
                recHotkeyRow.spacing = 8
                let recLabel = NSTextField(labelWithString: L10n.tr("录屏快捷键", "Recording Hotkey"))
                recLabel.font = .systemFont(ofSize: 12)
                recHotkeyRow.addArrangedSubview(recLabel)
                recRecorder = HotKeyRecorder()
                recRecorder.setAccessibilityLabel(L10n.tr("录屏快捷键录制器", "Recording hotkey recorder"))
                recRecorder.font = .systemFont(ofSize: 12)
                recRecorder.isBezeled = true
                recRecorder.bezelStyle = .roundedBezel
                recRecorder.isEditable = false
                recRecorder.alignment = .center
                recRecorder.placeholderString = L10n.tr("点击录制", "Click to record")
                recRecorder.onChange = { [weak self] code, mods in self?.applyRecHotKey(code: code, mods: mods) }
                recHotkeyRow.addArrangedSubview(recRecorder)
                recRecorder.widthAnchor.constraint(equalToConstant: 120).isActive = true
                recHotKeyHint = NSTextField(labelWithString: "")
                recHotKeyHint.font = .systemFont(ofSize: 11)
                recHotKeyHint.textColor = .systemRed
                recHotkeyRow.addArrangedSubview(recHotKeyHint)
                recInner.addArrangedSubview(recHotkeyRow)

                recSystemAudioCheck = NSButton(checkboxWithTitle: L10n.tr("录制系统声音(跟随画面)", "System audio (follow video)"), target: self, action: #selector(toggleRecSystemAudio))
                recInner.addArrangedSubview(recSystemAudioCheck)
                recMicCheck = NSButton(checkboxWithTitle: L10n.tr("录制麦克风", "Microphone"), target: self, action: #selector(toggleRecMic))
                recMicCheck.setAccessibilityHelp(L10n.tr("将麦克风声音录入视频。", "Record microphone audio into the video."))
                recInner.addArrangedSubview(recMicCheck)
                recInner.addArrangedSubview(separatorView())
                recCameraCheck = NSButton(checkboxWithTitle: L10n.tr("叠加摄像头画中画(录进视频,可拖动)", "Camera PiP (burn into video, draggable)"), target: self, action: #selector(toggleRecCamera))
                recCameraCheck.setAccessibilityHelp(L10n.tr("将可拖动的摄像头画中画合成到录屏中。", "Composite a draggable camera picture-in-picture into the recording."))
                recInner.addArrangedSubview(recCameraCheck)
                let camRow = NSStackView()
                camRow.orientation = .horizontal
                camRow.alignment = .centerY
                camRow.spacing = 8
                let camWLabel = NSTextField(labelWithString: L10n.tr("画中画宽度", "PiP Width"))
                camWLabel.font = .systemFont(ofSize: 11)
                camWLabel.textColor = .secondaryLabelColor
                camRow.addArrangedSubview(camWLabel)
                recCameraWidthSlider = NSSlider(value: 220, minValue: 120, maxValue: 360, target: self, action: #selector(cameraWidthChanged))
                recCameraWidthSlider.setAccessibilityLabel(L10n.tr("画中画宽度", "Picture-in-picture width"))
                recCameraWidthSlider.setAccessibilityHelp(L10n.tr("调整摄像头画中画宽度。", "Adjust the camera picture-in-picture width."))
                recCameraWidthSlider.controlSize = .small
                recCameraWidthSlider.translatesAutoresizingMaskIntoConstraints = false
                camRow.addArrangedSubview(recCameraWidthSlider)
                recCameraWidthSlider.widthAnchor.constraint(equalToConstant: 120).isActive = true
                recCameraWidthLabel = NSTextField(labelWithString: "220")
                recCameraWidthLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                recCameraWidthLabel.textColor = .secondaryLabelColor
                camRow.addArrangedSubview(recCameraWidthLabel)
                recInner.addArrangedSubview(camRow)
                recCameraCircleCheck = NSButton(checkboxWithTitle: L10n.tr("圆形裁切", "Circular crop"), target: self, action: #selector(toggleCameraCircle))
                recInner.addArrangedSubview(recCameraCircleCheck)
                recCameraMirrorCheck = NSButton(checkboxWithTitle: L10n.tr("镜像(前置摄像头常用)", "Mirror (front camera)"), target: self, action: #selector(toggleCameraMirror))
                recInner.addArrangedSubview(recCameraMirrorCheck)
                let camHint = NSTextField(labelWithString: L10n.tr("录制时会弹出可拖动的摄像头预览,拖到想要的位置后开始录/录制中也可拖,位置会自动记忆,合成进最终 .mov。首次需授权「摄像头」。", "A draggable camera preview appears before/during recording; position is remembered and composited into final .mov. Requires Camera permission."))
                camHint.font = .systemFont(ofSize: 10.5, weight: .regular)
                camHint.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.85)
                camHint.lineBreakMode = .byWordWrapping
                camHint.maximumNumberOfLines = 2
                camHint.preferredMaxLayoutWidth = 460
                recInner.addArrangedSubview(camHint)
                let recHint = NSTextField(labelWithString: L10n.tr("全屏 + 带声:默认带麦克风;若无需人声可关掉麦克风。", "Fullscreen + audio: mic on by default; turn off if you don't need voice."))
                recHint.font = .systemFont(ofSize: 10.5, weight: .regular)
                recHint.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.85)
                recInner.addArrangedSubview(recHint)

                let permissionsCard = permissionSummaryCard([
                    (L10n.tr("屏幕录制", "Screen Recording"), PermissionManager.isScreenCaptureTrusted, "screenCapture"),
                    (L10n.tr("摄像头", "Camera"), AVCaptureDevice.authorizationStatus(for: .video) == .authorized, "camera"),
                    (L10n.tr("麦克风", "Microphone"), AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, "microphone")
                ])
                recStack.addArrangedSubview(permissionsCard)
                permissionsCard.widthAnchor.constraint(equalTo: recStack.widthAnchor).isActive = true
                let recCard = cardBox(containing: recInner)
                recStack.addArrangedSubview(recCard)
                recCard.widthAnchor.constraint(equalTo: recStack.widthAnchor).isActive = true
                let recHint2 = NSTextField(labelWithString: L10n.tr("点击菜单栏「录屏」或按快捷键开始(3秒倒计时) → 顶部悬浮条显示时长 → 点停止保存到桌面。首次需授权「屏幕录制」/「麦克风」。", "Click menu bar Recording or hotkey to start (3s countdown) → top bar shows time → Stop to save to Desktop. Requires Screen Recording / Microphone."))
                recHint2.font = .systemFont(ofSize: 10.5, weight: .regular)
                recHint2.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.78)
                recHint2.lineBreakMode = .byWordWrapping
                recHint2.maximumNumberOfLines = 2
                recHint2.preferredMaxLayoutWidth = 460
                recStack.addArrangedSubview(recHint2)
                recTab.view = recView
                tabView.addTabViewItem(recTab)

    }
}
