import AppKit
import Foundation

/// 手动去隔离:面板拖入 + xattr -dr,无自动监听。
enum QuarantineHelper {

    /// 对指定路径逐个执行 xattr -dr com.apple.quarantine
    static func strip(paths: [String], completion: ((Int, Int) -> Void)? = nil) {
        guard !paths.isEmpty else { completion?(0, 0); return }
        DispatchQueue.global(qos: .utility).async {
            var ok = 0, fail = 0
            for p in paths {
                if runXattr(path: p) { ok += 1 } else { fail += 1 }
            }
            NSLog("[FlowBox] 去隔离完成:成功 \(ok) 失败 \(fail) \(paths)")
            DispatchQueue.main.async { completion?(ok, fail) }
        }
    }

    @discardableResult
    static func runXattr(path: String) -> Bool {
        // 先试普通权限
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-dr", "com.apple.quarantine", path]
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 { return true }
        } catch {
            NSLog("[FlowBox] xattr 启动失败 \(path): \(error)")
        }
        // /Applications 下常需管理员权限,弹一次授权重试
        let quoted = "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let cmd = "xattr -dr com.apple.quarantine \(quoted)"
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        var err: NSDictionary?
        if let scpt = NSAppleScript(source: script) {
            scpt.executeAndReturnError(&err)
            if err == nil { return true }
            NSLog("[FlowBox] 提权 xattr 失败 \(path): \(String(describing: err))")
        }
        return false
    }

    static func isQuarantined(path: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        proc.arguments = ["-p", "com.apple.quarantine", path]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch { return false }
    }
}
