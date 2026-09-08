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

        presenceStrangerCheck = NSButton(checkboxWithTitle: L10n.tr("陌生人也锁屏(需先注册主人脸)", "Lock on unfamiliar faces (enroll owner first)"), target: self, action: #selector(togglePresenceStranger))
        presenceStrangerCheck.setAccessibilityHelp(L10n.tr("开启后,摄像头看到人但不是主人脸也会锁屏。只认「是主人/不是主人」,不识别具体是谁,特征只存本机。", "When on, a face that doesn't match the owner also locks the screen. It only answers owner-or-not, never identifies who; the feature vector stays on your Mac."))
        inner.addArrangedSubview(presenceStrangerCheck)

        let strangerRow = NSStackView()
        strangerRow.orientation = .horizontal
        strangerRow.alignment = .centerY
        strangerRow.spacing = 8
        presenceEnrollButton = NSButton(title: L10n.tr("注册主人脸", "Enroll owner face"), target: self, action: #selector(enrollOwnerFace))
        presenceEnrollButton.bezelStyle = .rounded
        presenceEnrollButton.controlSize = .small
        strangerRow.addArrangedSubview(presenceEnrollButton)
        presenceOwnerStatusLabel = NSTextField(labelWithString: "")
        presenceOwnerStatusLabel.font = .systemFont(ofSize: 11)
        presenceOwnerStatusLabel.textColor = .secondaryLabelColor
        presenceOwnerStatusLabel.lineBreakMode = .byWordWrapping
        presenceOwnerStatusLabel.maximumNumberOfLines = 2
        presenceOwnerStatusLabel.preferredMaxLayoutWidth = 360
        strangerRow.addArrangedSubview(presenceOwnerStatusLabel)
        inner.addArrangedSubview(strangerRow)

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
        presenceStrangerCheck.state = pc.strangerLockEnabled ? .on : .off
        updateOwnerStatusLabel()
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
        let enrolling = PresenceMonitor.shared.isEnrolling
        presenceLockStepper.isEnabled = on
        presenceConfirmStepper.isEnabled = on
        presenceGraceStepper.isEnabled = on
        // 注册中锁定开关,避免中途改配置把看守状态机搞乱
        presenceCheck.isEnabled = !enrolling
        presenceStrangerCheck.isEnabled = !enrolling
        presenceSaveCheck.isEnabled = !enrolling
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

    @objc func togglePresenceStranger(_ sender: NSButton) {
        let on = sender.state == .on
        if on {
            // 开陌生人锁必须先有主人脸,否则开了也形同虚设
            guard config.presence.ownerFaceprint != nil else {
                sender.state = .off
                presenceOwnerStatusLabel.stringValue = L10n.tr(
                    "请先点「注册主人脸」,注册成功后再开此开关。",
                    "Enroll your face first, then turn this on."
                )
                return
            }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .denied, .restricted:
                sender.state = .off
                PermissionManager.openCameraSettings()
                return
            default:
                break
            }
        }
        config.presence.strangerLockEnabled = on
        save()
        updateOwnerStatusLabel()
    }

    @objc func enrollOwnerFace(_ sender: NSButton) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async { if granted { self?.enrollOwnerFace(sender) } }
                }
            } else {
                PermissionManager.openCameraSettings()
            }
            return
        }
        presenceEnrollButton.isEnabled = false
        presenceOwnerStatusLabel.stringValue = L10n.tr(
            "请正脸看镜头,保持光线充足,采集中…",
            "Look at the camera in good light, capturing…"
        )
        Task { @MainActor in
            PresenceMonitor.shared.startEnroll(
                progress: { [weak self] done, total in
                    self?.presenceOwnerStatusLabel.stringValue = L10n.tr(
                        "采集中 \(done)/\(total)…请正脸看镜头",
                        "Capturing \(done)/\(total)… look at the camera"
                    )
                },
                completion: { [weak self] ok in
                    guard let self else { return }
                    // 重读磁盘配置(注册结果由看守写入),再刷新界面
                    self.config = AppConfig.load()
                    self.presenceEnrollButton.isEnabled = true
                    self.updateOwnerStatusLabel()
                    self.updatePresenceControlsEnabled()
                    self.refreshPresenceStatus()
                    if ok, self.config.presence.strangerLockEnabled == false {
                        // 注册成功但开关没开:提示可开,不擅自替用户打开
                        self.presenceOwnerStatusLabel.stringValue += L10n.tr(
                            "可打开「陌生人也锁屏」生效。",
                            " You can now turn on stranger lock."
                        )
                    }
                }
            )
        }
    }

    /// 主人脸注册状态行:未注册/已注册/注册中
    func updateOwnerStatusLabel() {
        let pc = config.presence
        if pc.ownerFaceprint != nil {
            presenceOwnerStatusLabel.stringValue = L10n.tr(
                "✅ 主人脸已注册(特征仅存本机)。想换人/换环境请重新注册。",
                "✅ Owner face enrolled (stays on this Mac). Re-enroll to change person or lighting."
            )
        } else if PresenceMonitor.shared.isEnrolling {
            // 注册中由进度回调驱动文字,这里不动
        } else {
            presenceOwnerStatusLabel.stringValue = L10n.tr(
                "未注册主人脸。陌生人锁需先注册,否则开了也不生效。",
                "No owner face yet. Stranger lock needs enrollment first."
            )
        }
    }
}
