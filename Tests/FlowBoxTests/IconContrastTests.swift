import Testing
import SharedCore
import CoreGraphics
import Foundation

@Suite("IconContrast")
struct IconContrastTests {

    @Test func neutralDetection() {
        #expect(IconContrast.isNeutralPixel(r: 1, g: 1, b: 1))
        #expect(IconContrast.isNeutralPixel(r: 0, g: 0, b: 0))
        #expect(IconContrast.isNeutralPixel(r: 0.5, g: 0.5, b: 0.53))
        #expect(!IconContrast.isNeutralPixel(r: 1, g: 0.6, b: 0))
        #expect(!IconContrast.isNeutralPixel(r: 0.2, g: 0.8, b: 0.3))
    }

    @Test func monochromeGlyphIsTemplate() {
        // 深色菜单栏渲染出的近白图标 + 浅色菜单栏的黑图标 + 一个透明像素 + 一个彩色像素
        let px: [UInt8] = [
            255, 255, 255, 255,
            0, 0, 0, 255,
            0, 0, 0, 0,
            255, 153, 0, 255,
        ]
        guard let src = Self.makeRGBA(px, 4, 1) else { Issue.record("bitmap"); return }
        #expect(abs(IconContrast.neutralRatio(of: src) - 2.0 / 3.0) < 0.001)
        #expect(!IconContrast.isMonochrome(src))   // 三分之一彩色 → 不够格

        var glyph = [UInt8]()
        for _ in 0..<19 { glyph += [255, 255, 255, 255] }
        glyph += [255, 153, 0, 255]                // 单个彩色角标不影响判定
        guard let real = Self.makeRGBA(glyph, 20, 1) else { Issue.record("glyph bitmap"); return }
        #expect(IconContrast.isMonochrome(real))
    }

    @Test func colorfulIconIsNotTemplate() {
        let px: [UInt8] = [
            255, 60, 0, 255,
            0, 200, 90, 255,
            40, 90, 255, 255,
            255, 255, 255, 255,
        ]
        guard let src = Self.makeRGBA(px, 4, 1) else { Issue.record("bitmap"); return }
        #expect(!IconContrast.isMonochrome(src))
    }

    @Test func emptyImageHasNoNeutralPixels() {
        guard let src = Self.makeRGBA([0, 0, 0, 0, 0, 0, 0, 0], 2, 1) else { Issue.record("bitmap"); return }
        #expect(IconContrast.neutralRatio(of: src) == 0)
        #expect(!IconContrast.isMonochrome(src))
    }

    static func makeRGBA(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        guard let p = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: p, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
