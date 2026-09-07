import AppKit
import Darwin
import Foundation

/// 系统锁屏:供人脸在场看守离开时自动锁屏。
/// 等同  → 锁定屏幕(Ctrl+Cmd+Q),锁后必定要密码/Touch ID,系统不允许 App 绕过。
enum SystemLocker {

    static func lock(reason: String = "手动") {
        NSLog("[FlowBox] 锁屏(\(reason))")
        // 私有但全版本稳定的锁屏入口
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW) {
            defer { dlclose(handle) }
            if let sym = dlsym(handle, "SACLockScreenImmediate") {
                typealias Fn = @convention(c) () -> Void
                let fn = unsafeBitCast(sym, to: Fn.self)
                fn()
                return
            }
            NSLog("[FlowBox] 未找到 SACLockScreenImmediate: \(String(cString: dlerror()))")
        } else {
            NSLog("[FlowBox] dlopen login.framework 失败: \(String(cString: dlerror()))")
        }
        // 兜底:发系统级锁屏快捷键(需辅助功能/自动化权限)
        let src = "tell application \"System Events\" to keystroke \"q\" using {control down, command down}"
        var err: NSDictionary?
        if let scpt = NSAppleScript(source: src) {
            scpt.executeAndReturnError(&err)
            if err == nil { return }
            NSLog("[FlowBox] AppleScript 锁屏失败: \(String(describing: err))")
        }
        let p2 = Process()
        p2.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p2.arguments = ["displaysleepnow"]
        try? p2.run()
    }
}
