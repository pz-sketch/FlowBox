import CoreGraphics
import Foundation

/// 菜单栏状态项缩略图的「是否单色」判定。
///
/// 背景:`screencapture -l <windowID>` 抓到的状态项图标,是系统按**菜单栏外观**渲染出来的
/// 单色图形 —— 深色菜单栏给近白色,浅色菜单栏给近黑色。而收纳菜单的底色由 `NSMenu` 自己那套
/// 规则决定,跟菜单栏可以不一致(实测本机:深色壁纸 + 浅色菜单)。
///
/// 于是「白色图标落浅色菜单」几乎隐形,鼠标悬停时更糟:macOS 26 的悬停高亮是一枚**浅色胶囊**
/// (菜单未激活时),白图标在浅色胶囊上依然白成一片 —— 用户看到的就是「图标和背景都是白」。
///
/// 解法不是猜底色,也不是把像素统一改色(改色只能同时迁就浅/深两种底色,迁就不了高亮这第三种),
/// 而是**把单色图标标成模板图**交给 AppKit:模板图一律用「当前菜单文字色」重绘,
/// 普通态/悬停态 × 浅色菜单/深色菜单 四种组合全部可见。已用独立菜单程序逐行抓帧验证过。
///
/// 彩色图标(品牌 logo)不能这么处理 —— 模板会把它们压成单色剪影,所以先算灰阶占比再决定。
///
/// 不依赖 AppKit,便于单测覆盖。
public enum IconContrast {

    /// 饱和度低于该值的像素视为「灰阶」(单色模板图标)。
    public static let defaultSaturationThreshold: Double = 0.28

    /// 灰阶像素占比达到该值,就认定整图是单色图标。
    public static let defaultNeutralRatio: Double = 0.9

    /// alpha 低于该值的像素不参与统计(抗锯齿拖尾、全透明底)。
    public static let defaultAlphaFloor: Double = 0.05

    /// 判断一个像素是否「灰阶」(与色相无关的黑/白/灰)。
    ///
    /// - Parameters:
    ///   - r/g/b: **反预乘**后的 0...1 分量
    ///   - threshold: 饱和度阈值,`(max-min)/max` 小于它就算灰阶
    public static func isNeutralPixel(r: Double, g: Double, b: Double,
                                      threshold: Double = defaultSaturationThreshold) -> Bool {
        let mx = max(r, max(g, b))
        let mn = min(r, min(g, b))
        guard mx > 0 else { return true }        // 纯黑
        return (mx - mn) / mx < threshold
    }

    /// 不透明像素里「灰阶」像素的占比(0...1)。没有任何不透明像素时返回 0。
    ///
    /// 输入可以是任意 CGImage(含裁剪视图 —— 内部会重绘进一块干净缓冲,不吃父图的 bytesPerRow)。
    public static func neutralRatio(of image: CGImage,
                                    saturationThreshold: Double = defaultSaturationThreshold,
                                    alphaFloor: Double = defaultAlphaFloor) -> Double {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return 0 }

        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return 0 }

        var total = 0
        var neutral = 0
        for i in stride(from: 0, to: buf.count, by: 4) {
            let a = Double(buf[i + 3]) / 255
            guard a > alphaFloor else { continue }          // 全透明像素不算内容
            total += 1
            // 反预乘后再判色相,否则抗锯齿边缘会被当成有彩色
            let r = Double(buf[i])     / (a * 255)
            let g = Double(buf[i + 1]) / (a * 255)
            let b = Double(buf[i + 2]) / (a * 255)
            if isNeutralPixel(r: r, g: g, b: b, threshold: saturationThreshold) { neutral += 1 }
        }
        guard total > 0 else { return 0 }
        return Double(neutral) / Double(total)
    }

    /// 该图是否可以按模板图交给 AppKit 用菜单文字色重绘(见类型说明)。
    public static func isMonochrome(_ image: CGImage,
                                    saturationThreshold: Double = defaultSaturationThreshold,
                                    minRatio: Double = defaultNeutralRatio) -> Bool {
        neutralRatio(of: image, saturationThreshold: saturationThreshold) >= minRatio
    }
}
