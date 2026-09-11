import Testing
import SharedCore
import CoreGraphics

@Suite("IconTrim")
struct IconTrimTests {

    @Test func boundsAroundContent() {
        // 5x4 画布,内容在 (1,1)-(3,2);行优先、自上而下
        let w = 5, h = 4
        var alpha = [UInt8](repeating: 0, count: w * h)
        for y in 1...2 { for x in 1...3 { alpha[y * w + x] = 255 } }
        let box = IconTrim.contentBounds(alpha: alpha, width: w, height: h)
        #expect(box?.x == 1)
        #expect(box?.y == 1)
        #expect(box?.width == 3)
        #expect(box?.height == 2)
    }

    @Test func fullyTransparentYieldsNil() {
        // 调用方靠这个 nil 决定原样返回原图 —— 绝不能产出空图
        let box = IconTrim.contentBounds(alpha: [UInt8](repeating: 0, count: 20), width: 5, height: 4)
        #expect(box == nil)
    }

    @Test func subThresholdPixelsIgnored() {
        // 抗锯齿拖尾(alpha 10)不该被算成内容
        let w = 5, h = 4
        var alpha = [UInt8](repeating: 0, count: w * h)
        alpha[0] = 10
        alpha[2 * w + 4] = 200
        let box = IconTrim.contentBounds(alpha: alpha, width: w, height: h)
        #expect(box?.x == 4)
        #expect(box?.y == 2)
        #expect(box?.width == 1)
        #expect(box?.height == 1)
    }

    @Test func degenerateInputYieldsNil() {
        #expect(IconTrim.contentBounds(alpha: [], width: 0, height: 0) == nil)
    }

    @Test func paddedRectClampedAtEdges() {
        let r = IconTrim.paddedRect((x: 0, y: 0, width: 5, height: 4), imageWidth: 5, imageHeight: 4, padding: 2)
        #expect(r == CGRect(x: 0, y: 0, width: 5, height: 4))
    }

    @Test func paddedRectExpandsAroundContent() {
        let r = IconTrim.paddedRect((x: 2, y: 2, width: 1, height: 1), imageWidth: 5, imageHeight: 4, padding: 1)
        #expect(r == CGRect(x: 1, y: 1, width: 3, height: 3))
    }
}
