import CoreGraphics
import Foundation

/// 录屏转 GIF 的纯计算部分:由源视频时长/尺寸 + 用户选择的帧率/最大宽度,
/// 推出编码所需的全部参数(帧延迟、帧时间表、输出尺寸、输出文件名)。
/// 不依赖 AVFoundation/ImageIO,便于单测覆盖。
public struct GifEncodePlan: Equatable {

    /// GIF 帧延迟,单位:厘秒(1/100 秒,GIF 规范的时间精度)
    public let delayCS: Int
    /// 实际生效帧率(由 delayCS 反推,与所选 fps 可能略有出入)
    public let effectiveFPS: Double
    /// 总帧数
    public let frameCount: Int
    /// 每帧的采样时间点(秒),单调递增且都在时长内
    public let frameTimes: [Double]
    /// 输出尺寸(保持宽高比,宽高取偶)
    public let outW: Int
    public let outH: Int
    /// 源视频时长(秒)
    public let duration: Double

    /// 帧率范围:GIF 高帧率体积爆炸,上限 15;低于 2 动画太卡
    public static let fpsRange = 2...15
    /// 输出宽度下限;maxWidth 传 0 表示保持原始尺寸
    public static let minWidth = 160

    public init?(fps: Int, maxWidth: Int, sourceW: Int, sourceH: Int, duration: Double) {
        guard sourceW > 0, sourceH > 0, duration > 0, duration.isFinite else { return nil }
        let f = min(max(fps, Self.fpsRange.lowerBound), Self.fpsRange.upperBound)
        // GIF 帧延迟是整厘秒:先取整再反推实际帧率,保证帧间隔均匀(基于钳制后的帧率)
        let delay = max(2, Int((100.0 / Double(f)).rounded()))
        self.delayCS = delay
        self.effectiveFPS = 100.0 / Double(delay)

        let count = max(1, Int((duration * Double(f)).rounded(.down)))
        self.frameCount = count
        // 采样点落在 [0, duration - 半个帧间隔),避免请求恰好在文件末尾导致取帧失败
        let lastSafe = max(0, duration - 0.5 / Double(f))
        self.frameTimes = (0..<count).map { min(Double($0) / Double(f), lastSafe) }

        let maxW = maxWidth <= 0 ? sourceW : max(Self.minWidth, maxWidth)
        if maxW >= sourceW {
            self.outW = sourceW
            self.outH = sourceH
        } else {
            let scale = Double(maxW) / Double(sourceW)
            self.outW = Self.even(maxW)
            self.outH = Self.even(Int((Double(sourceH) * scale).rounded()))
        }
        self.duration = duration
    }

    /// 输出文件名:同名换扩展名
    public static func gifFileName(forVideoName videoName: String) -> String {
        let base = (videoName as NSString).deletingPathExtension
        return base + ".gif"
    }

    /// 把 track 的 preferredTransform 应用到 naturalSize,得到「实际显示尺寸」。
    ///
    /// 旋转/竖拍视频的 `naturalSize` 是**未旋转**的(如 640×360),
    /// 而 `AVAssetImageGenerator` 在 `appliesPreferredTrackTransform = true` 下返回的是**旋转后**的图(360×640)。
    /// 若直接拿 naturalSize 去算输出尺寸,宽高比对不上,画面会被拉伸。
    /// `CGSize.applying` 只走线性部分(不含平移),对交换宽高的 90° 旋转正好得到正确结果。
    public static func orientedSize(
        natural: CGSize,
        transform: CGAffineTransform
    ) -> (width: Int, height: Int) {
        let r = natural.applying(transform)
        return (
            max(0, Int(abs(r.width).rounded())),
            max(0, Int(abs(r.height).rounded()))
        )
    }

    /// GIF 虽不要求偶数尺寸,但取偶可避免某些缩放路径下的半像素采样
    private static func even(_ v: Int) -> Int {
        max(2, v & ~1)
    }
}
