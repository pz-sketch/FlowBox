import AppKit
import ApplicationServices
import SharedCore
import CoreGraphics
import AVFoundation
import os

/// 权限检测模块:统一处理辅助功能/屏幕录制等 TCC 权限,避免重复弹窗。
enum PermissionManager {

    // MARK: - 辅助功能(Accessibility) - 滚轮反转/平滑滚动必需

    /// 当前是否已获辅助功能权限(无弹窗)
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 触发系统授权弹窗(若未授权),同时把当前签名写入 TCC
    @discardableResult
    static func requestAccessibilityPrompt() -> Bool {
        FlowLog.permission.info("请求辅助功能权限弹窗")
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let result = AXIsProcessTrustedWithOptions(opts)
        FlowLog.permission.info("辅助功能弹窗结果 trusted=\(result)")
        return result
    }

    /// 是否能成功创建 CGEventTap(区分辅助功能 vs 输入监控)
    static func canCreateEventTap() -> Bool {
        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, _ -> Unmanaged<CGEvent>? in Unmanaged.passUnretained(event) },
            userInfo: nil
        ) {
            CFMachPortInvalidate(tap)
            return true
        }
        return false
    }

    /// 综合判定:真正可用(系统认 + 能建 tap)
    static var isEffectivelyTrusted: Bool {
        isAccessibilityTrusted && canCreateEventTap()
    }

    /// 等待系统写入 TCC(用户刚点完允许后,tccd 有延迟),轮询最多 3 秒
    @discardableResult
    static func waitForTrust(timeout: TimeInterval = 3.0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isEffectivelyTrusted { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return isEffectivelyTrusted
    }

    // MARK: - 屏幕录制 - 菜单栏收纳/截图/录屏必需

    static var isScreenCaptureTrusted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 触发屏幕录制授权弹窗(首次)
    static func requestScreenCapture() {
        FlowLog.permission.info("请求屏幕录制权限弹窗")
        CGRequestScreenCaptureAccess()
    }

    // MARK: - 打开系统设置

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openScreenCaptureSettings() {
        // macOS 13+ 通用路径,旧版也会重定向
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 诊断

    /// 返回人类可读的权限状态,用于设置页展示
    static func accessibilityStatusText() -> (text: String, ok: Bool) {
        if isAccessibilityTrusted {
            return canCreateEventTap() ? (L10n.tr("✅ 已授权", "✅ Granted"), true) : (L10n.tr("⚠️ 辅助功能已开,但输入监控未开或需重启", "⚠️ Accessibility on, but Input Monitoring off or restart required"), false)
        }
        return (L10n.tr("⚠️ 未授权", "⚠️ Not granted"), false)
    }

    static func screenCaptureStatusText() -> (text: String, ok: Bool) {
        isScreenCaptureTrusted ? (L10n.tr("✅ 已授权", "✅ Granted"), true) : (L10n.tr("⚠️ 未授权", "⚠️ Not granted"), false)
    }

    // MARK: - 摄像头 - 人脸看守/录屏画中画必需

    static var isCameraTrusted: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    /// 触发摄像头授权弹窗(首次)
    static func requestCameraAccess(completion: ((Bool) -> Void)? = nil) {
        FlowLog.permission.info("请求摄像头权限弹窗")
        AVCaptureDevice.requestAccess(for: .video) { granted in
            FlowLog.permission.info("摄像头弹窗结果 granted=\(granted)")
            completion?(granted)
        }
    }

    static func cameraStatusText() -> (text: String, ok: Bool) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return (L10n.tr("✅ 已授权", "✅ Granted"), true)
        case .notDetermined:
            return (L10n.tr("尚未请求,开启看守时弹窗", "Not requested yet — prompts on enable"), false)
        case .denied, .restricted:
            return (L10n.tr("⚠️ 未授权,请在系统设置中允许", "⚠️ Denied — allow in System Settings"), false)
        @unknown default:
            return (L10n.tr("⚠️ 未知状态", "⚠️ Unknown"), false)
        }
    }

    static func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }
}
