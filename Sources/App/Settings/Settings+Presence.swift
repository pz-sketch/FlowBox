import AppKit
import AVFoundation
import SharedCore

extension SettingsWindowController {
    func buildPresenceTab(tabView: NSTabView) {
        // ========== Tab 6: 人脸看守 ==========
        let tab = NSTabViewItem(identifier: "presence")
        tab.label = L10n.tr("人脸", "Presence")
        let view = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
        ])

        stack.addArrangedSubview(
            sectionHeader(
                L10n.tr("人脸看守", "Presence Watch"),
                subtitle: L10n.tr("本地 AI 检测人脸:离开自动锁屏,纯本机处理,不联网不存图", "On-device face detection: auto-lock when you leave, never leaves your Mac"),
                symbol: "person.crop.circle.badge.checkmark"
            )
        )

        let cameraCard = permissionStatusCard(
            name: L10n.tr("摄像头 / Camera", "Camera"),
            purpose: L10n.tr("用于本地人脸在场检测,画面只进内存做矩形检测,不保存不上传。", "Used only for on-device presence detection; frames stay in memory, never saved or uploaded."),
            granted: PermissionManager.isCameraTrusted,
            settingsKey: "camera"
        )
        stack.addArrangedSubview(cameraCard)
        cameraCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 12

        presenceCheck = NSButton(checkboxWithTitle: L10n.tr("离开自动锁屏(无操作超时后确认,无人则锁)", "Auto-lock when away (checks after idle, locks if empty)"), target: self, action: #selector(togglePresence))
        presenceCheck.setAccessibilityHelp(L10n.tr("开启后感应键鼠空闲,超时才短暂开摄像头确认,无人则自动锁屏。", "When on, watches for keyboard/mouse idle, briefly confirms with the camera, and locks if no one is there."))
        inner.addArrangedSubview(presenceCheck)

        presenceStatusHint = NSTextField(labelWithString: "")
        presenceStatusHint.font = .systemFont(ofSize: 11)
        presenceStatusHint.textColor = .secondaryLabelColor
        presenceStatusHint.lineBreakMode = .byWordWrapping
        presenceStatusHint.maximumNumberOfLines = 2
        presenceStatusHint.preferredMaxLayoutWidth = 460
        inner.addArrangedSubview(presenceStatusHint)

        inner.addArrangedSubview(separatorView())

        // 1) 无操作多少秒后开始检测
        presenceLockStepper = makePresenceStepper(min: 3, max: 30, increment: 1, defaultValue: 8, action: #selector(presenceLockChanged))
        let lockRow = NSStackView()
        lockRow.orientation = .horizontal
        lockRow.alignment = .centerY
        lockRow.spacing = 8
        let lockLabel = NSTextField(labelWithString: L10n.tr("无操作多久后检测(秒)", "Idle before checking (s)"))
        lockLabel.font = .systemFont(ofSize: 12)
        lockRow.addArrangedSubview(lockLabel)
        lockRow.addArrangedSubview(presenceLockStepper)
        presenceLockValueLabel = NSTextField(labelWithString: "8s")
        presenceLockValueLabel.font = .systemFont(ofSize: 11)
        presenceLockValueLabel.textColor = .secondaryLabelColor
        presenceLockValueLabel.alignment = .right
        presenceLockValueLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
        lockRow.addArrangedSubview(presenceLockValueLabel)
        inner.addArrangedSubview(lockRow)

        // 2) 确认有人后多久复查(检测间隔)
        presenceConfirmStepper = makePresenceStepper(min: 10, max: 300, increment: 10, defaultValue: 60, action: #selector(presenceConfirmChanged))
        let confirmRow = NSStackView()
        confirmRow.orientation = .horizontal
        confirmRow.alignment = .centerY
        confirmRow.spacing = 8
        let confirmLabel = NSTextField(labelWithString: L10n.tr("检测间隔(每多久复查,秒)", "Recheck every (s)"))
        confirmLabel.font = .systemFont(ofSize: 12)
        confirmRow.addArrangedSubview(confirmLabel)
        confirmRow.addArrangedSubview(presenceConfirmStepper)
        presenceConfirmValueLabel = NSTextField(labelWithString: "60s")
        presenceConfirmValueLabel.font = .systemFont(ofSize: 11)
        presenceConfirmValueLabel.textColor = .secondaryLabelColor
        presenceConfirmValueLabel.alignment = .right
        presenceConfirmValueLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
        confirmRow.addArrangedSubview(presenceConfirmValueLabel)
        inner.addArrangedSubview(confirmRow)

        // 3) 宽限期
        presenceGraceStepper = makePresenceStepper(min: 5, max: 60, increment: 5, defaultValue: 15, action: #selector(presenceGraceChanged))
        let graceRow = NSStackView()
        graceRow.orientation = .horizontal
        graceRow.alignment = .centerY
        graceRow.spacing = 8
        let graceLabel = NSTextField(labelWithString: L10n.tr("开启/解锁后宽限(秒)", "Grace after unlock (s)"))
        graceLabel.font = .systemFont(ofSize: 12)
        graceRow.addArrangedSubview(graceLabel)
        graceRow.addArrangedSubview(presenceGraceStepper)
        presenceGraceValueLabel = NSTextField(labelWithString: "15s")
        presenceGraceValueLabel.font = .systemFont(ofSize: 11)
        presenceGraceValueLabel.textColor = .secondaryLabelColor
        presenceGraceValueLabel.alignment = .right
        presenceGraceValueLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
        graceRow.addArrangedSubview(presenceGraceValueLabel)
        inner.addArrangedSubview(graceRow)

        inner.addArrangedSubview(separatorView())

        presenceSaveCheck = NSButton(checkboxWithTitle: L10n.tr("锁屏前保存摄像头快照(排查误锁用)", "Save camera snapshot before locking (debug)"), target: self, action: #selector(togglePresenceSave))
        presenceSaveCheck.setAccessibilityHelp(L10n.tr("确认无人并即将锁屏时,把那刻画面存到本机 presence-cap 目录,方便核对当时是否真的没人。只留本机,可随时删除。", "When a lock is about to happen, save that frame to the local presence-cap folder to verify whether anyone was really there. Stays on your Mac; feel free to delete."))
        inner.addArrangedSubview(presenceSaveCheck)

        let saveHint = NSTextField(labelWithString: L10n.tr("保存位置:配置文件同目录下的 Presence-cap 子文件夹,只有无人判定触发锁屏时才写。", "Saved under the Presence-cap folder next to your config; written only when a no-face check triggers a lock."))
        saveHint.font = .systemFont(ofSize: 10.5, weight: .regular)
        saveHint.textColor = NSColor.secondaryLabelColor.withAlphaComponent(0.85)
        saveHint.lineBreakMode = .byWordWrapping
        saveHint.maximumNumberOfLines = 2
        saveHint.preferredMaxLayoutWidth = 460
        inner.addArrangedSubview(saveHint)

        inner.addArrangedSubview(separatorView())

        let note = NSTextField(labelWithString: L10n.tr(
            "说明:无操作满第 1 个秒数后开始开摄像头检测人脸;确认有人且仍无操作,每隔第 2 个秒数复查一次;一旦有操作重新累计第 1 个秒数。锁屏后看守休眠不再亮灯。锁屏后必须输密码或 Touch ID 才能进入,这是 macOS 安全限制,任何 App 都不能自动解锁。录屏占用摄像头时看守自动让路。",
            "After idle past the 1st value the camera checks your face; if you're there and still idle, it rechecks every (2nd value); any input restarts the 1st countdown. After locking the watch sleeps. After locking you must enter your password or Touch ID — macOS never lets apps unlock for you. The watch yields while recording uses the camera."
        ))
        note.font = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 6
        note.preferredMaxLayoutWidth = 460
        inner.addArrangedSubview(note)

        let card = cardBox(containing: inner)
        stack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        tab.view = view
        tabView.addTabViewItem(tab)
    }

    func reloadPresenceControls() {
        let pc = config.presence
        presenceCheck.state = pc.enabled ? .on : .off
        presenceLockStepper.doubleValue = pc.lockAfterSeconds
        presenceLockValueLabel.stringValue = "\(Int(pc.lockAfterSeconds))s"
        presenceConfirmStepper.doubleValue = pc.confirmAfterSeconds
        presenceConfirmValueLabel.stringValue = "\(Int(pc.confirmAfterSeconds))s"
        presenceGraceStepper.doubleValue = pc.gracePeriod
        presenceGraceValueLabel.stringValue = "\(Int(pc.gracePeriod))s"
        presenceSaveCheck.state = pc.saveCaptureOnLock ? .on : .off
        updatePresenceControlsEnabled()
        refreshPresenceStatus()
    }

    /// 人脸时间参数统一用上下步进器,不用滑杆
    private func makePresenceStepper(
        min: Double,
        max: Double,
        increment: Double,
        defaultValue: Double,
        action: Selector
    ) -> NSStepper {
        let stepper = NSStepper()
        stepper.minValue = min
        stepper.maxValue = max
        stepper.increment = increment
        stepper.doubleValue = defaultValue
        stepper.valueWraps = false
        stepper.controlSize = .small
        stepper.target = self
        stepper.action = action
        stepper.setAccessibilityLabel(L10n.tr("上下选择秒数", "Adjust seconds"))
        return stepper
    }

    func updatePresenceControlsEnabled() {
        let on = presenceCheck.state == .on
        presenceLockStepper.isEnabled = on
        presenceConfirmStepper.isEnabled = on
        presenceGraceStepper.isEnabled = on
    }

    func refreshPresenceStatus() {
        Task { @MainActor in
            let t = PresenceMonitor.shared.statusText()
            self.presenceStatusHint.stringValue = t
            let s = PermissionManager.cameraStatusText()
            if !s.ok, self.config.presence.enabled {
                self.presenceStatusHint.stringValue = t + " · " + s.text
            }
            self.presenceStatusHint.textColor = PresenceMonitor.shared.isMonitoring ? NSColor.systemGreen : NSColor.secondaryLabelColor
        }
    }

    @objc func togglePresence(_ sender: NSButton) {
        let on = sender.state == .on
        if on {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if granted {
                            self.config.presence.enabled = true
                            self.save()
                            Task { @MainActor in PresenceMonitor.shared.start(grace: self.config.presence.gracePeriod) }
                        } else {
                            self.presenceCheck.state = .off
                        }
                        self.updatePresenceControlsEnabled()
                        self.refreshPresenceStatus()
                    }
                }
                updatePresenceControlsEnabled()
                return
            case .denied, .restricted:
                sender.state = .off
                PermissionManager.openCameraSettings()
                refreshPresenceStatus()
                updatePresenceControlsEnabled()
                return
            case .authorized:
                break
            @unknown default:
                break
            }
        }
        config.presence.enabled = on
        save()
        Task { @MainActor in PresenceMonitor.shared.refresh() }
        updatePresenceControlsEnabled()
        refreshPresenceStatus()
    }

    @objc func presenceLockChanged(_ sender: NSStepper) {
        config.presence.lockAfterSeconds = sender.doubleValue
        presenceLockValueLabel.stringValue = "\(Int(sender.doubleValue))s"
        save()
    }

    @objc func presenceConfirmChanged(_ sender: NSStepper) {
        config.presence.confirmAfterSeconds = sender.doubleValue
        presenceConfirmValueLabel.stringValue = "\(Int(sender.doubleValue))s"
        save()
    }

    @objc func presenceGraceChanged(_ sender: NSStepper) {
        config.presence.gracePeriod = sender.doubleValue
        presenceGraceValueLabel.stringValue = "\(Int(sender.doubleValue))s"
        save()
    }

    @objc func togglePresenceSave(_ sender: NSButton) {
        config.presence.saveCaptureOnLock = sender.state == .on
        save()
    }
}
