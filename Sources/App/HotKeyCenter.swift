import AppKit
import Carbon.HIToolbox

/// 全局快捷键:基于 Carbon RegisterEventHotKey,无需「辅助功能」权限
/// 支持多快捷键(截图 + 录屏),每个 hotKey 以 id 区分
final class HotKeyCenter {

    static let shared = HotKeyCenter()

    enum Kind: UInt32 { case screenshot = 1, recording = 2 }

    /// 快捷键触发回调(主线程异步)
    var onTrigger: (() -> Void)?
    var onRecordTrigger: (() -> Void)?
    /// 设置里录制新快捷键时暂停触发,避免录制动作直接启动截图
    var isPaused = false
    /// 菜单展开时是否可见(由 MenuBarHider 设置)
    var isMenuVisible: (() -> Bool)?

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false

    private func ensureHandler() -> Bool {
        if installed { return true }
        var spec = EventTypeSpec(
            eventClass: EventClass(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                if center.isPaused { return noErr }
                var hotID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotID)
                let kind = hotID.id
                DispatchQueue.main.async {
                    if kind == HotKeyCenter.Kind.recording.rawValue { center.onRecordTrigger?() }
                    else { center.onTrigger?() }
                }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil
        )
        installed = status == noErr
        if !installed { NSLog("[FlowBox] 快捷键事件处理器安装失败: \(status)") }
        return installed
    }

    /// 注册单条快捷键;false 多为被其它应用占用
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, kind: Kind = .screenshot) -> Bool {
        guard ensureHandler() else { return false }
        if let old = refs[kind.rawValue] { UnregisterEventHotKey(old); refs.removeValue(forKey: kind.rawValue) }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x5243484B), id: kind.rawValue)
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let r = ref else {
            NSLog("[FlowBox] 快捷键注册失败(\(kind)): \(status)")
            return false
        }
        refs[kind.rawValue] = r
        return true
    }

    /// 兼容旧调用:默认注册截图
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        register(keyCode: keyCode, modifiers: modifiers, kind: .screenshot)
    }

    func unregister(kind: Kind) {
        if let ref = refs[kind.rawValue] { UnregisterEventHotKey(ref); refs.removeValue(forKey: kind.rawValue) }
    }

    func unregister() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    // MARK: - 按键显示

    /// Carbon 修饰键掩码 → "⌃⌥⇧⌘"(固定顺序)
    static func modifierString(_ modifiers: UInt32) -> String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s
    }

    /// Carbon 虚拟键码 → 可读字符(A、1、F5、空格…),未知键码显示编号
    static func keyName(_ keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
            23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
            34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P",
            12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
            49: "空格", 48: "Tab", 36: "回车", 51: "删除", 117: "⌦", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'",
            43: ",", 47: ".", 44: "/", 50: "`",
        ]
        return names[keyCode] ?? "Key(\(keyCode))"
    }

    static func comboName(keyCode: UInt32, modifiers: UInt32) -> String {
        modifierString(modifiers) + keyName(keyCode)
    }
}
