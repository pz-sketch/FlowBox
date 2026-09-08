import Foundation
import SharedCore

var passed = 0, failed = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { passed += 1; print("✅ \(msg)") }
    else { failed += 1; print("❌ \(msg)") }
}
func checkEq<T: Equatable>(_ a: T, _ b: T, _ msg: String) { check(a==b, "\(msg) (\(a) == \(b))") }
func checkNear(_ a: Double, _ b: Double, _ msg: String) { check(abs(a-b) < 0.01, "\(msg) (\(a) ≈ \(b))") }

// Helpers
func hotKeyModifierString(_ mods: UInt32) -> String {
    var s=""; if mods & 4096 != 0 { s+="⌃" }; if mods & 2048 != 0 { s+="⌥" }; if mods & 512 != 0 { s+="⇧" }; if mods & 256 != 0 { s+="⌘" }; return s
}
func hotKeyName(_ code: UInt32) -> String { let m:[UInt32:String]=[0:"A",15:"R",53:"Esc",36:"回车",49:"空格",122:"F1"]; return m[code] ?? "Key(\(code))" }
func scaledDelta(_ d: Double, ms: Double) -> Double { d*ms/60.0 }
func shouldStop(_ r: Double) -> Bool { abs(r) < 0.6 }
func easedStep(_ r: Double) -> Double { r*0.5 }
func clamped(_ v: Double) -> Double { min(120,max(10,v)) }
struct Pip { let x:CGFloat; let y:CGFloat; let w:Int; let h:Int }
func pipLayout(cfg: RecordingConfig, W:Int, H:Int, scale:CGFloat) -> Pip {
    let isCircle=cfg.cameraIsCircle; let pwpt=max(120,min(360,cfg.cameraWidth)); let pw=Int(pwpt*scale); let ph=isCircle ? pw : pw*9/16
    let margin:CGFloat=16*scale; var px:CGFloat, py:CGFloat
    if cfg.cameraX<0||cfg.cameraY<0 { px=CGFloat(W)-CGFloat(pw)-margin; py=margin }
    else { let nx=min(1,max(0,cfg.cameraX)), ny=min(1,max(0,cfg.cameraY)); px=nx*CGFloat(W-pw); py=ny*CGFloat(H-ph) }
    px=min(max(0,px),CGFloat(W-pw)); py=min(max(0,py),CGFloat(H-ph))
    return Pip(x:px,y:py,w:pw,h:ph)
}

print("=== FlowBox Core Tests (CLT runner) ===")

// Config
do {
    let cfg=AppConfig.defaultConfig()
    check(cfg.menu.copyFolder==true, "default menu.copyFolder true")
    check(cfg.newFiles.count>=1, "default newFiles >=1")
    checkNear(cfg.scroll.minStep, 60, "default scroll.minStep 60")
    checkNear(cfg.screenshot.penWidth, 4, "default penWidth 4")
    check(cfg.recording.frameRate==30, "default frameRate 30")
    check(cfg.presence.enabled==false, "default presence off")
    checkNear(cfg.presence.lockAfterSeconds, 8, "default lockAfter 8s")
    checkNear(cfg.presence.confirmAfterSeconds, 60, "default confirmAfter 60s")
    checkNear(cfg.presence.gracePeriod, 15, "default grace 15s")
    check(cfg.presence.saveCaptureOnLock==true, "default saveCaptureOnLock true")
    check(cfg.presence.strangerLockEnabled==false, "default strangerLock off")
    check(cfg.presence.ownerFaceprint==nil, "default ownerFaceprint nil")
    checkNear(cfg.presence.ownerMatchThreshold, 0.6, "default ownerThreshold 0.6")
}
do {
    var cfg=AppConfig.defaultConfig(); cfg.menu.copyFolder=false; cfg.scroll.smoothScrolling=true; cfg.scroll.minStep=120; cfg.screenshot.penColorHex="#00FF00"; cfg.recording.captureCamera=true; cfg.recording.cameraWidth=260
    let data=try! JSONEncoder().encode(cfg); let dec=try! JSONDecoder().decode(AppConfig.self, from:data)
    check(dec.scroll.minStep==120, "roundtrip minStep 120")
    check(dec.screenshot.penColorHex=="#00FF00", "roundtrip penColor")
    check(dec.recording.captureCamera==true, "roundtrip camera")
    check(dec.recording.cameraWidth==260, "roundtrip cameraWidth")
    var pcfg=AppConfig.defaultConfig(); pcfg.presence.enabled=true; pcfg.presence.lockAfterSeconds=12; pcfg.presence.confirmAfterSeconds=90; pcfg.presence.gracePeriod=20; pcfg.presence.saveCaptureOnLock=false; pcfg.presence.strangerLockEnabled=true; pcfg.presence.ownerFaceprint=[0.1, 0.2, 0.3]; pcfg.presence.ownerMatchThreshold=0.7
    let pdata=try! JSONEncoder().encode(pcfg); let pdec=try! JSONDecoder().decode(AppConfig.self, from:pdata)
    check(pdec.presence.enabled==true, "roundtrip presence on")
    checkNear(pdec.presence.lockAfterSeconds, 12, "roundtrip lockAfter 12s")
    checkNear(pdec.presence.confirmAfterSeconds, 90, "roundtrip confirmAfter 90s")
    checkNear(pdec.presence.gracePeriod, 20, "roundtrip grace 20s")
    check(pdec.presence.saveCaptureOnLock==false, "roundtrip saveCaptureOnLock off")
    check(pdec.presence.strangerLockEnabled==true, "roundtrip strangerLock on")
    check(pdec.presence.ownerFaceprint==[0.1, 0.2, 0.3], "roundtrip ownerFaceprint")
    checkNear(pdec.presence.ownerMatchThreshold, 0.7, "roundtrip ownerThreshold 0.7")
}
do {
// Faceprint 纯数值比对(余弦相似度 + 多帧平均),不依赖摄像头
    checkNear(Faceprint.cosineSimilarity([1, 0, 0], [1, 0, 0]), 1, "cosine identical 1")
    checkNear(Faceprint.cosineSimilarity([1, 0], [-1, 0]), -1, "cosine opposite -1")
    checkNear(Faceprint.cosineSimilarity([1, 0], [0, 1]), 0, "cosine orthogonal 0")
    check(Faceprint.cosineSimilarity([], [])==0, "cosine empty 0")
    check(Faceprint.cosineSimilarity([1, 2], [1])==0, "cosine dim mismatch 0")
    check(Faceprint.average([])==nil, "average empty nil")
    let m=Faceprint.average([[1, 2], [3, 4]])
    check(m != nil && abs((m?[0] ?? 0)-2)<0.01 && abs((m?[1] ?? 0)-3)<0.01, "average mean")
}
do {
    let json=#"{"menu":{"copyFolder":true},"scroll":{}}"#.data(using:.utf8)!
    let dec=try! JSONDecoder().decode(AppConfig.self, from:json)
    check(dec.menu.copyFolder==true, "backward copyFolder")
    check(dec.scroll.minStep==60, "backward minStep default")
    check(dec.scroll.smoothScrolling==false, "backward smooth false")
    check(dec.presence.enabled==false, "backward presence default off")
}
do {
    let a=NewFileItem(name:"X",filename:"x.docx",content:"aaa",encoding:"base64")
    check(a.isBase64==true, "base64 true")
    check(NewFileItem(name:"Y",filename:"y.txt",content:"hi").isBase64==false, "base64 false")
    check(NewFileItem(name:"A",filename:"a.md",content:"# hi")==NewFileItem(name:"A",filename:"a.md",content:"# hi"), "equatable")
}
do {
    let c=ScreenshotConfig()
    check(c.hotKeyCode==0 && c.hotKeyModifiers==2048 && c.penColorHex=="#FF3B30" && c.mosaicBlock==16, "screenshot defaults")
    let r=RecordingConfig()
    check(r.hotKeyCode==15 && r.captureSystemAudio && r.captureMicrophone && !r.captureCamera && r.cameraWidth==220 && r.cameraX == -1 && r.cameraIsCircle, "recording defaults")
}
do {
    var c=ScrollConfig(); c.minStep=500; check(min(120,max(10,c.minStep))==120, "clamp 500->120")
    c.minStep=2; check(min(120,max(10,c.minStep))==10, "clamp 2->10")
}
do {
    check(RCCommand.copy(text:"hi")?.scheme=="flowbox", "RC copy scheme")
    check(RCCommand.copy(text:"hi")?.host=="copy", "RC copy host")
    check(RCCommand.terminal(dir:"/tmp")?.host=="terminal", "RC terminal")
    check(RCCommand.newFile(dir:"/tmp",index:0)?.host=="newfile", "RC newFile")
    check(RCCommand.stripQuarantine(paths:["/a","/b"]) != nil, "RC strip not nil")
    check(RCCommand.stripQuarantine(paths:[])==nil, "RC strip empty nil")
    check(ConfigStore.configURL.path.contains("net.ai2048.flowbox.ext"), "configURL bundle")
    check(ConfigStore.configURL.path.hasSuffix("config.json"), "configURL suffix")
    check(!ConfigStore.realHomePath.isEmpty && ConfigStore.realHomePath.hasPrefix("/"), "realHomePath")
}

// HotKey
check(hotKeyModifierString(2048)=="⌥", "mod ⌥")
check(hotKeyModifierString(2048|256)=="⌥⌘", "mod ⌥⌘")
check(hotKeyModifierString(0)=="", "mod empty")
check(hotKeyModifierString(4096|2048|512|256)=="⌃⌥⇧⌘", "mod order")
check(hotKeyName(0)=="A" && hotKeyName(15)=="R" && hotKeyName(53)=="Esc", "keyName")
check(hotKeyName(999).hasPrefix("Key("), "keyName unknown")
check(hotKeyModifierString(2048)+hotKeyName(0)=="⌥A", "combo ⌥A")
check(hotKeyModifierString(2048)+hotKeyName(15)=="⌥R", "combo ⌥R")

// Scroll
checkNear(scaledDelta(10, ms:60), 10, "scaled 60")
checkNear(scaledDelta(10, ms:120), 20, "scaled 120")
checkNear(scaledDelta(10, ms:30), 5, "scaled 30")
check(shouldStop(0.5)==true, "shouldStop 0.5")
check(shouldStop(0.7)==false, "shouldStop 0.7")
checkNear(easedStep(10), 5, "eased 10")
check(clamped(5)==10 && clamped(300)==120 && clamped(60)==60, "clamped")
do { var r=100.0, s=0; while !shouldStop(r) && s<20 { r-=easedStep(r); s+=1 }; check(shouldStop(r) && s<20 && s>5, "convergence steps \(s)") }
checkNear(-scaledDelta(10, ms:60), -10, "reverse")

// Compositor
do {
    var cfg=RecordingConfig(); cfg.cameraWidth=220; cfg.cameraX = -1; cfg.cameraY = -1; cfg.cameraIsCircle=true
    let l=pipLayout(cfg:cfg,W:2880,H:1800,scale:2)
    check(l.w==440 && l.h==440, "pip default size")
    checkNear(Double(l.x), Double(2880-440-32), "pip default x")
    checkNear(Double(l.y), 32, "pip default y")
}
do {
    var cfg=RecordingConfig(); cfg.cameraWidth=200; cfg.cameraIsCircle=false
    let l=pipLayout(cfg:cfg,W:1920,H:1080,scale:1)
    check(l.w==200 && l.h==112, "pip rect")
}
do {
    var cfg=RecordingConfig(); cfg.cameraWidth=500; check(pipLayout(cfg:cfg,W:1000,H:800,scale:1).w==360, "pip clamp 500")
    cfg.cameraWidth=50; check(pipLayout(cfg:cfg,W:1000,H:800,scale:1).w==120, "pip clamp 50")
}
do {
    var cfg=RecordingConfig(); cfg.cameraWidth=220; cfg.cameraIsCircle=true; cfg.cameraX=0.5; cfg.cameraY=0.5
    let l=pipLayout(cfg:cfg,W:2000,H:1000,scale:1)
    checkNear(Double(l.x), Double((2000-220)/2), "pip normalized x")
    checkNear(Double(l.y), Double((1000-220)/2), "pip normalized y")
}
do {
    var cfg=RecordingConfig(); cfg.cameraX=2; cfg.cameraY = -1
    let l=pipLayout(cfg:cfg,W:1000,H:800,scale:1)
    check(l.x>=0 && l.x<=CGFloat(1000-l.w), "pip bounds")
}
do {
    var cfg=RecordingConfig(); cfg.cameraIsCircle=true; cfg.cameraWidth=220
    let l=pipLayout(cfg:cfg,W:1920,H:1080,scale:1); let r=min(l.w,l.h)/2
    check(r==110, "circle radius")
}
do {
    var cfg=RecordingConfig(); cfg.cameraX = -1
    let l=pipLayout(cfg:cfg,W:3440,H:1440,scale:2)
    check(l.x+CGFloat(l.w)<3440 && l.y>0, "notch bounds")
}

print("\n=== Result: \(passed) passed, \(failed) failed ===")
if failed>0 { exit(1) }
