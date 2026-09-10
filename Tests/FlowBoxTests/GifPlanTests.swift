import Testing
import SharedCore
import Foundation

@Suite("GifPlan")
struct GifPlanTests {

    @Test func basic() {
        // 10s 视频,10fps,2880 宽缩到 960
        let p = GifEncodePlan(fps: 10, maxWidth: 960, sourceW: 2880, sourceH: 1800, duration: 10)!
        #expect(p.frameCount == 100)
        #expect(p.delayCS == 10)
        #expect(abs(p.effectiveFPS - 10) < 0.01)
        #expect(p.outW == 960)
        #expect(p.outH == 600)
        #expect(p.frameTimes.count == 100)
        #expect(p.frameTimes.first == 0)
        #expect(abs(p.frameTimes.last! - 9.9) < 0.001)
    }

    @Test func fpsClampedToRange() {
        // fps 60 → 钳到 15:delay = round(100/15) = 7 厘秒(≈14.3fps),帧数按 15fps
        let hi = GifEncodePlan(fps: 60, maxWidth: 960, sourceW: 1920, sourceH: 1080, duration: 2)!
        #expect(hi.delayCS == 7)
        #expect(abs(hi.effectiveFPS - 100.0 / 7.0) < 0.001)
        #expect(hi.frameCount == 30)  // 2s * 15fps
        let lo = GifEncodePlan(fps: 1, maxWidth: 960, sourceW: 1920, sourceH: 1080, duration: 4)!
        #expect(lo.delayCS == 50)     // 钳到 2fps → 0.5s
        #expect(lo.frameCount == 8)   // 4s * 2fps
    }

    @Test func noUpscale() {
        // maxWidth 0 或大于源宽 → 保持原始尺寸
        let a = GifEncodePlan(fps: 10, maxWidth: 0, sourceW: 1440, sourceH: 900, duration: 5)!
        #expect(a.outW == 1440 && a.outH == 900)
        let b = GifEncodePlan(fps: 10, maxWidth: 4000, sourceW: 1440, sourceH: 900, duration: 5)!
        #expect(b.outW == 1440 && b.outH == 900)
    }

    @Test func minWidthFloorAndEvenDims() {
        // 极小宽度抬到 160,且宽高都是偶数
        let p = GifEncodePlan(fps: 10, maxWidth: 100, sourceW: 1921, sourceH: 1081, duration: 3)!
        #expect(p.outW == 160)
        #expect(p.outW % 2 == 0 && p.outH % 2 == 0)
        #expect(p.outH == 90)  // 1081*160/1921 ≈ 90.02 → 90
    }

    @Test func invalidInput() {
        #expect(GifEncodePlan(fps: 10, maxWidth: 960, sourceW: 0, sourceH: 100, duration: 5) == nil)
        #expect(GifEncodePlan(fps: 10, maxWidth: 960, sourceW: 100, sourceH: 100, duration: 0) == nil)
        #expect(GifEncodePlan(fps: 10, maxWidth: 960, sourceW: 100, sourceH: 100, duration: -1) == nil)
        #expect(GifEncodePlan(fps: 10, maxWidth: 960, sourceW: 100, sourceH: 100, duration: .infinity) == nil)
    }

    @Test func timesWithinDuration() {
        // 超短视频:至少 1 帧,采样点都落在时长内且单调
        let p = GifEncodePlan(fps: 15, maxWidth: 480, sourceW: 1920, sourceH: 1080, duration: 0.05)!
        #expect(p.frameCount == 1)
        #expect(p.frameTimes == [0])
        let q = GifEncodePlan(fps: 15, maxWidth: 480, sourceW: 1920, sourceH: 1080, duration: 0.35)!
        #expect(q.frameCount == 5)
        #expect(zip(q.frameTimes, q.frameTimes.dropFirst()).allSatisfy { $1 > $0 })
        #expect(q.frameTimes.allSatisfy { $0 >= 0 && $0 < 0.35 })
    }

    @Test func fileNameMapping() {
        #expect(GifEncodePlan.gifFileName(forVideoName: "录屏 2026-09-10 143000.mov") == "录屏 2026-09-10 143000.gif")
        #expect(GifEncodePlan.gifFileName(forVideoName: "a.b.mp4") == "a.b.gif")
        #expect(GifEncodePlan.gifFileName(forVideoName: "noext") == "noext.gif")
    }

    @Test func orientedSizeAppliesPreferredTransform() {
        // 竖拍/旋转视频:naturalSize 未旋转,抽帧返回的是旋转后的图,必须按 transform 校正
        let natural = CGSize(width: 640, height: 360)
        let id = GifEncodePlan.orientedSize(natural: natural, transform: .identity)
        #expect(id.width == 640 && id.height == 360)

        let r90 = GifEncodePlan.orientedSize(natural: natural, transform: CGAffineTransform(rotationAngle: .pi / 2))
        #expect(r90.width == 360 && r90.height == 640)

        let r270 = GifEncodePlan.orientedSize(natural: natural, transform: CGAffineTransform(rotationAngle: -.pi / 2))
        #expect(r270.width == 360 && r270.height == 640)

        let r180 = GifEncodePlan.orientedSize(natural: natural, transform: CGAffineTransform(rotationAngle: .pi))
        #expect(r180.width == 640 && r180.height == 360)
    }

    @Test func portraitPlanKeepsAspect() {
        // 校正后按竖屏尺寸出计划:宽 320 → 高 568,而不是被压成 320x180
        let portrait = GifEncodePlan(fps: 10, maxWidth: 320, sourceW: 360, sourceH: 640, duration: 2)!
        #expect(portrait.outW == 320 && portrait.outH == 568)
        let landscape = GifEncodePlan(fps: 10, maxWidth: 320, sourceW: 640, sourceH: 360, duration: 2)!
        #expect(landscape.outH == 180)
        #expect(portrait.outH != landscape.outH)
    }
}
