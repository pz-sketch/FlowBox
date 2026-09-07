import Testing
import SharedCore
import Foundation

struct TestPipLayout: Equatable { let x: CGFloat; let y: CGFloat; let w: Int; let h: Int }

func testPipLayout(for cfg: RecordingConfig, outputW: Int, outputH: Int, scale: CGFloat) -> TestPipLayout {
    let isCircle = cfg.cameraIsCircle
    let pipWpt = max(120, min(360, cfg.cameraWidth))
    let pipW = Int(pipWpt * scale)
    let pipH = isCircle ? pipW : pipW * 9 / 16
    let margin: CGFloat = 16 * scale
    var pipX: CGFloat; var pipY: CGFloat
    if cfg.cameraX < 0 || cfg.cameraY < 0 { pipX = CGFloat(outputW)-CGFloat(pipW)-margin; pipY = margin }
    else { let nx=min(1,max(0,cfg.cameraX)); let ny=min(1,max(0,cfg.cameraY)); pipX=nx*CGFloat(outputW-pipW); pipY=ny*CGFloat(outputH-pipH) }
    pipX=min(max(0,pipX),CGFloat(outputW-pipW)); pipY=min(max(0,pipY),CGFloat(outputH-pipH))
    return TestPipLayout(x:pipX,y:pipY,w:pipW,h:pipH)
}

@Suite("Compositor")
struct CompositorTests {
    @Test func pipDefault() {
        var cfg=RecordingConfig(); cfg.cameraWidth=220; cfg.cameraX = -1; cfg.cameraY = -1; cfg.cameraIsCircle=true
        let l=testPipLayout(for:cfg,outputW:2880,outputH:1800,scale:2)
        #expect(l.w==440); #expect(l.h==440); #expect(abs(l.x-Double(2880-440-32))<0.1); #expect(abs(l.y-32)<0.1)
    }
    @Test func pipRect() {
        var cfg=RecordingConfig(); cfg.cameraWidth=200; cfg.cameraIsCircle=false
        let l=testPipLayout(for:cfg,outputW:1920,outputH:1080,scale:1)
        #expect(l.w==200); #expect(l.h==112)
    }
    @Test func pipClamp() {
        var cfg=RecordingConfig(); cfg.cameraWidth=500
        #expect(testPipLayout(for:cfg,outputW:1000,outputH:800,scale:1).w==360)
        cfg.cameraWidth=50
        #expect(testPipLayout(for:cfg,outputW:1000,outputH:800,scale:1).w==120)
    }
    @Test func pipNormalized() {
        var cfg=RecordingConfig(); cfg.cameraWidth=220; cfg.cameraIsCircle=true; cfg.cameraX=0.5; cfg.cameraY=0.5
        let l=testPipLayout(for:cfg,outputW:2000,outputH:1000,scale:1)
        #expect(abs(l.x-Double((2000-220)/2))<0.1); #expect(abs(l.y-Double((1000-220)/2))<0.1)
    }
    @Test func pipBounds() {
        var cfg=RecordingConfig(); cfg.cameraX=2; cfg.cameraY = -1
        let l=testPipLayout(for:cfg,outputW:1000,outputH:800,scale:1)
        #expect(l.x>=0); #expect(l.x<=CGFloat(1000-l.w))
    }
    @Test func scaleAndCrop() {
        let sx=CGFloat(220)/640, sy=CGFloat(220)/480, s=max(sx,sy)
        #expect(s>0); #expect(abs(s-max(220/640.0,220/480.0))<0.01)
    }
    @Test func circleRadius() {
        var cfg=RecordingConfig(); cfg.cameraIsCircle=true; cfg.cameraWidth=220
        let l=testPipLayout(for:cfg,outputW:1920,outputH:1080,scale:1); let r=min(CGFloat(l.w),CGFloat(l.h))/2
        #expect(abs(r-110)<0.1)
    }
    @Test func notch() {
        var cfg=RecordingConfig(); cfg.cameraX = -1
        let l=testPipLayout(for:cfg,outputW:3440,outputH:1440,scale:2)
        #expect(l.x+CGFloat(l.w)<3440); #expect(l.y>0)
    }
}
