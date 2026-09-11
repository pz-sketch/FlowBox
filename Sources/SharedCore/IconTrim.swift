import CoreGraphics
import Foundation

/// 菜单栏状态项缩略图的裁剪计算。
///
/// `screencapture -l <windowID>` 抓到的是一整个状态项窗口(本机实测 76x66 像素 @2x),
/// 图标本体只占中间一小块(约 40x32),四周全是透明边 —— 直接缩到 16pt 会糊成一团。
/// 这里算出「非透明像素」的包围盒,只保留图标本体。
///
/// 不依赖 AppKit,便于单测覆盖。
public enum IconTrim {

    /// 非透明像素的包围盒(左上原点、像素坐标)。
    ///
    /// - Parameters:
    ///   - alpha: 行优先、自上而下的 alpha 数组,长度需 >= width*height
    ///   - threshold: alpha 大于该值算「有内容」;默认 26(≈10%),滤掉抗锯齿拖尾
    /// - Returns: 包围盒;整张图全透明(或入参非法)时返回 nil
    public static func contentBounds(alpha: [UInt8], width: Int, height: Int,
                                     threshold: UInt8 = 26) -> (x: Int, y: Int, width: Int, height: Int)? {
        guard width > 0, height > 0, alpha.count >= width * height else { return nil }
        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            let row = y * width
            for x in 0..<width where alpha[row + x] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }

    /// 把包围盒外扩 padding 并夹在图内,得到可直接传给 `CGImage.cropping(to:)` 的矩形
    public static func paddedRect(_ box: (x: Int, y: Int, width: Int, height: Int),
                                  imageWidth: Int, imageHeight: Int,
                                  padding: Int = 1) -> CGRect {
        let x = max(0, box.x - padding)
        let y = max(0, box.y - padding)
        let w = max(1, min(imageWidth - x, box.width + padding * 2))
        let h = max(1, min(imageHeight - y, box.height + padding * 2))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// 抽取 CGImage 的 alpha 通道(行优先、自上而下)。失败返回 nil。
    public static func alphaMap(of image: CGImage) -> [UInt8]? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h)
        let ok = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? buf : nil
    }

    /// 一步到位:裁掉透明边距。
    ///
    /// 图没有 alpha 通道、全透明、或本来就贴边时,**原样返回**(绝不返回空图)。
    public static func trimmed(_ image: CGImage, threshold: UInt8 = 26, padding: Int = 1) -> CGImage {
        guard let alpha = alphaMap(of: image),
              let box = contentBounds(alpha: alpha, width: image.width, height: image.height, threshold: threshold)
        else { return image }
        let rect = paddedRect(box, imageWidth: image.width, imageHeight: image.height, padding: padding)
        guard rect.width < CGFloat(image.width) || rect.height < CGFloat(image.height) else { return image }
        return image.cropping(to: rect) ?? image
    }
}
