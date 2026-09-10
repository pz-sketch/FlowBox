import AppKit
import ImageIO
import QuickLookUI

// MARK: - 转换/保存完成后的 Quick Look 预览窗
//
// 用 QLPreviewView(自带完整 Quick Look 渲染)而不是 QLPreviewPanel:
// 后者要求响应链上有对象实现 acceptsPreviewPanelControl: 来接管,
// 而 FlowBox 是菜单栏应用,转换面板关闭后此刻没有 key window,
// 直接 makeKeyAndOrderFront 很容易弹出"面板在但内容空白"。
// QLPreviewView 的渲染与窗口生命周期都是自己管的,动图会直接循环播放。

@MainActor
final class QuickLookPreviewWindow: NSObject, NSWindowDelegate {

    static let shared = QuickLookPreviewWindow()

    private var window: NSWindow?

    private override init() { super.init() }

    /// 弹出预览窗播放文件(动图直接播)。
    /// 返回 false 表示 Quick Look 视图不可用,调用方应自行降级(提示 + Finder 选中)。
    @discardableResult
    func preview(_ url: URL) -> Bool {
        dismissPrevious()

        let content = Self.contentSize(for: url)
        guard let view = QLPreviewView(frame: NSRect(origin: .zero, size: content), style: .normal) else {
            return false
        }
        view.autostarts = true
        view.shouldCloseWithWindow = true

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: content),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.title = url.lastPathComponent
        // 标题栏副标题给出所在目录,代替「在 Finder 中选中」的定位作用
        win.subtitle = (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        win.delegate = self
        win.collectionBehavior.insert(.fullScreenAuxiliary)

        view.translatesAutoresizingMaskIntoConstraints = false
        win.contentView?.addSubview(view)
        if let cv = win.contentView {
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: cv.topAnchor),
                view.leadingAnchor.constraint(equalTo: cv.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: cv.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: cv.bottomAnchor),
            ])
        }
        window = win

        view.previewItem = url as NSURL
        view.refreshPreviewItem()

        NSApp.activate(ignoringOtherApps: true)
        win.center()
        win.makeKeyAndOrderFront(nil)
        // 上屏后再刷一次:QLPreviewView 在未入窗时设 previewItem 有概率不渲染首帧
        view.refreshPreviewItem()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
    }

    private func dismissPrevious() {
        window?.orderOut(nil)
        window = nil
    }

    // MARK: 窗口尺寸

    /// 按 GIF 像素尺寸定窗口,并夹在屏幕可见范围内
    private static func contentSize(for url: URL) -> NSSize {
        let fallback = NSSize(width: 640, height: 420)
        guard let px = pixelSize(of: url) else { return fallback }
        let maxW: CGFloat = 1080, maxH: CGFloat = 720
        let scale = min(1, maxW / px.width, maxH / px.height)
        var w = max(280, px.width * scale)
        var h = max(200, px.height * scale)
        if let vis = NSScreen.main?.visibleFrame {
            w = min(w, vis.width * 0.9)
            h = min(h, vis.height * 0.85)
        }
        return NSSize(width: w.rounded(), height: h.rounded())
    }

    private static func pixelSize(of url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
        else { return nil }
        let w = (props[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue ?? 0
        let h = (props[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue ?? 0
        guard w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }
}
