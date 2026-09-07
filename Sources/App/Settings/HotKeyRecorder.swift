import AppKit
import SharedCore
import Carbon.HIToolbox
import os

/// 快捷键录制框:点击进入录制,按下组合键生效,Esc 取消,点击别处恢复原值
final class HotKeyRecorder: NSTextField {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        styleField()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); styleField() }

    func styleField() {
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.14).cgColor
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        isBezeled = true
        bezelStyle = .roundedBezel
        font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textColor = .labelColor
        alignment = .center
    }

    var onChange: ((UInt32, UInt32) -> Void)?
    /// 当前已保存的组合键显示文本(录制前暂存)
    var savedName: String = ""

    private var recording = false

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { startRecording() }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        if recording {
            recording = false
            HotKeyCenter.shared.isPaused = false
            stringValue = savedName
        }
        return super.resignFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard recording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 53 { // Esc 取消
            finishRecording(newValue: nil)
            return
        }
        var mods: UInt32 = 0
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { mods |= UInt32(cmdKey) }
        if flags.contains(.option) { mods |= UInt32(optionKey) }
        if flags.contains(.control) { mods |= UInt32(controlKey) }
        if flags.contains(.shift) { mods |= UInt32(shiftKey) }
        // 必须带修饰键(Shift 不算)或为 F 键,避免误占普通字符键
        let fKeyCodes: Set<Int> = [
            96, 97, 98, 100, 101, 103, 109, 111, 105, 107, 113, 106, 64, 79, 80,
            118, 120, 99, 122,
        ]
        let hasRealModifier = mods != 0 && mods != UInt32(shiftKey)
        guard hasRealModifier || (mods == 0 && fKeyCodes.contains(Int(event.keyCode))) else {
            NSSound.beep()
            return
        }
        let name = HotKeyCenter.comboName(keyCode: UInt32(event.keyCode), modifiers: mods)
        FlowLog.hotkey.info("HotKeyRecorder 录制: \(name, privacy: .public)")
        onChange?(UInt32(event.keyCode), mods)
        finishRecording(newValue: name)
    }

    private func updateBorder(accent: Bool) {
        layer?.borderColor = (accent ? NSColor.controlAccentColor : NSColor.separatorColor.withAlphaComponent(0.14)).cgColor
        layer?.borderWidth = accent ? 1.5 : 1
    }
    private func startRecording() {
        guard !recording else { return }
        recording = true
        if !stringValue.isEmpty { savedName = stringValue }
        stringValue = L10n.tr("按下新快捷键…", "Press a new shortcut…")
        updateBorder(accent: true)
        HotKeyCenter.shared.isPaused = true
    }

    private func finishRecording(newValue: String?) {
        recording = false
        HotKeyCenter.shared.isPaused = false
        updateBorder(accent: false)
        if let v = newValue {
            savedName = v
            stringValue = v
        } else {
            stringValue = savedName
        }
        window?.makeFirstResponder(nil)
    }
}
