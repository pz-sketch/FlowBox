import Foundation
import CoreGraphics
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
// GifPlan 录屏转 GIF 纯计算
do {
    let p=GifEncodePlan(fps:10,maxWidth:960,sourceW:2880,sourceH:1800,duration:10)!
    checkEq(p.frameCount, 100, "gif basic frameCount")
    checkEq(p.delayCS, 10, "gif basic delayCS")
    checkEq(p.outW, 960, "gif basic outW")
    checkEq(p.outH, 600, "gif basic outH")
    checkNear(p.frameTimes.last ?? 0, 9.9, "gif basic last time")
    let hi=GifEncodePlan(fps:60,maxWidth:960,sourceW:1920,sourceH:1080,duration:2)!
    checkEq(hi.delayCS, 7, "gif fps60 clamped delay 7cs")
    checkEq(hi.frameCount, 30, "gif fps60 clamped count 2s*15")
    let lo=GifEncodePlan(fps:1,maxWidth:960,sourceW:1920,sourceH:1080,duration:4)!
    checkEq(lo.delayCS, 50, "gif fps1 clamped delay 50cs")
    let a=GifEncodePlan(fps:10,maxWidth:0,sourceW:1440,sourceH:900,duration:5)!
    check(a.outW==1440 && a.outH==900, "gif width0 keeps original")
    let tiny=GifEncodePlan(fps:10,maxWidth:100,sourceW:1921,sourceH:1081,duration:3)!
    checkEq(tiny.outW, 160, "gif minWidth floor 160")
    check(tiny.outW%2==0 && tiny.outH%2==0, "gif even dims")
    check(GifEncodePlan(fps:10,maxWidth:960,sourceW:0,sourceH:100,duration:5)==nil, "gif invalid sourceW nil")
    check(GifEncodePlan(fps:10,maxWidth:960,sourceW:100,sourceH:100,duration:0)==nil, "gif invalid duration nil")
    let sh=GifEncodePlan(fps:15,maxWidth:480,sourceW:1920,sourceH:1080,duration:0.05)!
    checkEq(sh.frameCount, 1, "gif short video 1 frame")
    checkEq(GifEncodePlan.gifFileName(forVideoName:"录屏 2026-09-10 143000.mov"), "录屏 2026-09-10 143000.gif", "gif filename mapping")
    // 旧配置兼容:缺 gif 字段时回落默认值
    let legacy=#"{"recording":{"frameRate":30}}"#.data(using:.utf8)!
    let lc=try! JSONDecoder().decode(AppConfig.self, from:legacy)
    checkEq(lc.recording.gifFps, 10, "gif legacy config default fps")
    checkEq(lc.recording.gifMaxWidth, 960, "gif legacy config default width")
}
// preferredTransform 尺寸校正:竖拍视频若只用 naturalSize 会被拉伸
do {
    let nat=CGSize(width:640,height:360)
    let id=GifEncodePlan.orientedSize(natural:nat,transform:.identity)
    check(id.width==640 && id.height==360, "gif oriented identity 640x360 (got \(id.width)x\(id.height))")
    let r90=GifEncodePlan.orientedSize(natural:nat,transform:CGAffineTransform(rotationAngle:.pi/2))
    check(r90.width==360 && r90.height==640, "gif oriented 90deg → 360x640 (got \(r90.width)x\(r90.height))")
    let r270=GifEncodePlan.orientedSize(natural:nat,transform:CGAffineTransform(rotationAngle:-.pi/2))
    check(r270.width==360 && r270.height==640, "gif oriented -90deg → 360x640 (got \(r270.width)x\(r270.height))")
    let r180=GifEncodePlan.orientedSize(natural:nat,transform:CGAffineTransform(rotationAngle:.pi))
    check(r180.width==640 && r180.height==360, "gif oriented 180deg → 640x360 (got \(r180.width)x\(r180.height))")
    // 校正后再算 plan:竖拍 360x640 → 宽 320 时高 568,宽高比保持(不是被压成 320x180)
    let p=GifEncodePlan(fps:10,maxWidth:320,sourceW:r90.width,sourceH:r90.height,duration:2)!
    check(p.outW==320 && p.outH==568, "gif portrait plan 320x568 (got \(p.outW)x\(p.outH))")
    let bad=GifEncodePlan(fps:10,maxWidth:320,sourceW:640,sourceH:360,duration:2)!
    check(bad.outH != p.outH, "gif unrotated vs rotated plans differ (regression guard)")
}

// 截图选区拖动:位移夹取 + 矩形/顶点同步平移
do {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let rect = CGRect(x: 100, y: 100, width: 200, height: 150)

    // 界内正常平移
    let inRange = SelectionGeometry.clampedDelta(rect: rect, bounds: bounds, dx: 50, dy: -30)
    checkEq(inRange, CGPoint(x: 50, y: -30), "selection delta in range")
    let movedInRange = SelectionGeometry.offset(rect, by: inRange)
    checkEq(movedInRange, CGRect(x: 150, y: 70, width: 200, height: 150), "selection rect offset in range")

    // 四向超界夹取(选区尺寸保持不变)
    let rMax = SelectionGeometry.clampedDelta(rect: rect, bounds: bounds, dx: 9999, dy: 9999)
    checkEq(rMax, CGPoint(x: 700, y: 550), "selection delta clamped to right/bottom")
    let rMin = SelectionGeometry.clampedDelta(rect: rect, bounds: bounds, dx: -9999, dy: -9999)
    checkEq(rMin, CGPoint(x: -100, y: -100), "selection delta clamped to left/top")

    // 夹取后必然完整落在屏幕内,且尺寸不变
    for d in [CGPoint(x: 9999, y: 9999), CGPoint(x: -9999, y: -9999), CGPoint(x: 500, y: -400), CGPoint(x: 12, y: 7)] {
        let delta = SelectionGeometry.clampedDelta(rect: rect, bounds: bounds, dx: d.x, dy: d.y)
        let moved = SelectionGeometry.offset(rect, by: delta)
        check(bounds.contains(moved), "selection stays in bounds for desired \(d) → \(delta)")
        checkEq(moved.size, rect.size, "selection size unchanged for desired \(d)")
    }

    // 退化:选区比屏幕还大 → 零位移,不允许乱滑
    let huge = CGRect(x: -20, y: -20, width: 1200, height: 900)
    let degenerate = SelectionGeometry.clampedDelta(rect: huge, bounds: bounds, dx: 100, dy: 100)
    checkEq(degenerate, .zero, "oversized selection yields zero delta")

    // 标注顶点与选区共用同一位移,相对位置保持不变
    let points = [CGPoint(x: 120, y: 130), CGPoint(x: 260, y: 210)]
    let shifted = SelectionGeometry.offset(points, by: CGPoint(x: 50, y: -30))
    checkEq(shifted, [CGPoint(x: 170, y: 100), CGPoint(x: 310, y: 180)], "annotation points shifted with selection")
    let relativeBefore = CGPoint(x: points[0].x - rect.minX, y: points[0].y - rect.minY)
    let relativeAfter = CGPoint(x: shifted[0].x - movedInRange.minX, y: shifted[0].y - movedInRange.minY)
    checkEq(relativeAfter, relativeBefore, "annotation keeps position relative to selection")
    let untouched = SelectionGeometry.offset(points, by: .zero)
    checkEq(untouched, points, "zero delta leaves annotation points untouched")
}

// 状态项缩略图裁剪:找非透明像素的包围盒。
// (菜单栏状态项窗口 76x66,图标只占中间约 40x32,不裁边直接缩到 16pt 会糊成一坨)
do {
    let w = 5, h = 4
    // 内容在 (1,1)-(3,2),行优先、自上而下
    var alpha = [UInt8](repeating: 0, count: w * h)
    for y in 1...2 { for x in 1...3 { alpha[y * w + x] = 255 } }
    let box = IconTrim.contentBounds(alpha: alpha, width: w, height: h)
    checkEq(box?.x ?? -1, 1, "icon trim bounds minX")
    checkEq(box?.y ?? -1, 1, "icon trim bounds minY")
    checkEq(box?.width ?? -1, 3, "icon trim bounds width")
    checkEq(box?.height ?? -1, 2, "icon trim bounds height")

    // 全透明 → nil(调用方应原样返回原图,绝不产出空图)
    let emptyBox = IconTrim.contentBounds(alpha: [UInt8](repeating: 0, count: w * h), width: w, height: h)
    check(emptyBox == nil, "icon trim returns nil for fully transparent image")

    // 低于阈值的抗锯齿拖尾不算内容
    var faint = [UInt8](repeating: 0, count: w * h)
    faint[0] = 10                 // < 26:忽略
    faint[2 * w + 4] = 200        // 保留
    let faintBox = IconTrim.contentBounds(alpha: faint, width: w, height: h)
    checkEq(faintBox?.x ?? -1, 4, "icon trim ignores sub-threshold pixels (minX)")
    checkEq(faintBox?.y ?? -1, 2, "icon trim ignores sub-threshold pixels (minY)")

    // 退化入参 → nil,不能崩
    check(IconTrim.contentBounds(alpha: [], width: 0, height: 0) == nil, "icon trim rejects degenerate input")

    // padding 外扩,并夹在图内(不能超过边界)
    checkEq(IconTrim.paddedRect((x: 0, y: 0, width: 5, height: 4), imageWidth: w, imageHeight: h, padding: 2),
            CGRect(x: 0, y: 0, width: 5, height: 4), "padded rect clamped at image edges")
    checkEq(IconTrim.paddedRect((x: 2, y: 2, width: 1, height: 1), imageWidth: w, imageHeight: h, padding: 1),
            CGRect(x: 1, y: 1, width: 3, height: 3), "padded rect expands around content")
}

// 菜单条目文字取舍:机器标识/纯英文一律退回纯图标
do {
    checkEq(MenuLabel.displayable("omlx.metric.live"), "", "drop domain-style menu title")
    checkEq(MenuLabel.displayable("com.tencent.xinWeChat"), "", "drop bundle-id menu title")
    checkEq(MenuLabel.displayable("BentoBox-0"), "", "drop autosaveName menu title")
    checkEq(MenuLabel.displayable("WiFi"), "", "drop plain-english menu title")
    checkEq(MenuLabel.displayable("12345"), "", "drop numeric menu title")
    checkEq(MenuLabel.displayable("聚焦"), "聚焦", "keep chinese menu title")
    checkEq(MenuLabel.displayable("  电池  "), "电池", "trim whitespace around menu title")
    checkEq(MenuLabel.displayable("微信 WeChat"), "微信 WeChat", "keep mixed cjk and ascii title")
    checkEq(MenuLabel.displayable(""), "", "empty menu title stays empty")
    checkEq(MenuLabel.displayable("   "), "", "whitespace-only menu title stays empty")
    check(MenuLabel.containsCJK("输入法"), "detects cjk characters")
    check(!MenuLabel.containsCJK("Autofill"), "rejects pure ascii text")
    // 标题兜底:永远非空,不许出现空标题/`?` 行(包名/窗口名都可以显示)
    checkEq(MenuLabel.fallbackTitle(winName: "com.tencent.qq", bundleID: nil, windowNumber: 1), "com.tencent.qq", "fallback shows package name as-is")
    checkEq(MenuLabel.fallbackTitle(winName: "  电池  ", bundleID: nil, windowNumber: 2), "电池", "fallback trims whitespace")
    checkEq(MenuLabel.fallbackTitle(winName: "Item-0", bundleID: nil, windowNumber: 8617), "菜单栏图标 8617", "fallback disambiguates anonymous items by window number")
    checkEq(MenuLabel.fallbackTitle(winName: "", bundleID: "com.tencent.qq", windowNumber: 3), "com.tencent.qq", "fallback uses bundleID for empty window name")
    checkEq(MenuLabel.fallbackTitle(winName: "", bundleID: nil, windowNumber: 4), "菜单栏图标 4", "fallback never returns empty")
}

// 状态项配对:跨屏副本命名 + 位置键宽度自检(两条都必须「宁缺毋滥」)
do {
    check(!StatusItemPairing.isIdentifiableName(""), "empty window name is not an identity")
    check(!StatusItemPairing.isIdentifiableName("   "), "whitespace window name is not an identity")
    check(!StatusItemPairing.isIdentifiableName("Item-0"), "Item-0 is anonymous")
    check(!StatusItemPairing.isIdentifiableName("Item-12"), "Item-N is anonymous")
    check(StatusItemPairing.isIdentifiableName("com.tencent.qq"), "bundle id counts as identity")
    check(StatusItemPairing.isIdentifiableName("WiFi"), "system window name counts as identity")
    check(StatusItemPairing.looksLikeBundleID("com.tencent.qq"), "bundle id form is recognized")
    check(!StatusItemPairing.looksLikeBundleID("WiFi"), "dotless system name is not a bundle id")
    check(!StatusItemPairing.looksLikeBundleID("Bento Box.1"), "name with a space is not a bundle id")

    // 本机实测形态:主屏 7 个匿名 Item-0,外接屏同 7 个带 bundle id,两侧宽度序列一致
    let anon = [
        StatusWindow(number: 8203, x: 880,  width: 38, name: "Item-0"),
        StatusWindow(number: 7789, x: 918,  width: 32, name: "Item-0"),
        StatusWindow(number: 55,   x: 950,  width: 32, name: "Item-0"),
        StatusWindow(number: 8852, x: 982,  width: 38, name: "Item-0"),
        StatusWindow(number: 91,   x: 1020, width: 34, name: "Item-0"),
        StatusWindow(number: 52,   x: 1054, width: 44, name: "Item-0"),
        StatusWindow(number: 95,   x: 1098, width: 38, name: "Item-0"),
    ]
    let named = [
        StatusWindow(number: 8619, x: 2798, width: 38, name: "com.tencent.workbuddy.mac"),
        StatusWindow(number: 8617, x: 2836, width: 32, name: "com.tencent.qq"),
        StatusWindow(number: 8608, x: 2868, width: 32, name: "com.apple.Spotlight"),
        StatusWindow(number: 8854, x: 2900, width: 38, name: "com.tencent.xinWeChat"),
        StatusWindow(number: 8610, x: 2938, width: 34, name: "io.github.clash-verge-rev.clash-verge-rev"),
        StatusWindow(number: 8607, x: 2972, width: 44, name: "com.apple.TextInputMenuAgent"),
        StatusWindow(number: 8614, x: 3016, width: 38, name: "ndsc-gui"),
    ]
    let mapped = StatusItemPairing.crossScreenNames(recipients: anon, donors: named)
    checkEq(mapped.count, 7, "cross-screen naming covers every anonymous item")
    checkEq(mapped[7789] ?? "", "com.tencent.qq", "width 32 + x-order pins QQ to the right window")
    checkEq(mapped[8203] ?? "", "com.tencent.workbuddy.mac", "width 38 disambiguates workbuddy")
    checkEq(mapped[8852] ?? "", "com.tencent.xinWeChat", "same-width group keeps x-order for wechat")
    checkEq(mapped[91] ?? "", "io.github.clash-verge-rev.clash-verge-rev", "unique width 34 maps clash")
    checkEq(mapped[95] ?? "", "ndsc-gui", "trailing width 38 maps ndsc")

    // 数量不等 / 宽度对不上 / 两侧同名冲突 → 整批放弃(名字宁可不显示)
    check(StatusItemPairing.crossScreenNames(recipients: anon, donors: Array(named.dropLast())).isEmpty,
          "count mismatch aborts the whole batch")
    var skewed = named
    skewed[0] = StatusWindow(number: 8619, x: 2798, width: 50, name: "com.tencent.workbuddy.mac")
    check(StatusItemPairing.crossScreenNames(recipients: anon, donors: skewed).isEmpty,
          "width multiset mismatch aborts the whole batch")
    let clashR = [StatusWindow(number: 1, x: 10, width: 38, name: "com.a.one"),
                  StatusWindow(number: 2, x: 20, width: 38, name: "com.b.two")]
    let clashD = [StatusWindow(number: 3, x: 80, width: 38, name: "com.b.two"),
                  StatusWindow(number: 4, x: 90, width: 38, name: "com.a.one")]
    check(StatusItemPairing.crossScreenNames(recipients: clashR, donors: clashD).isEmpty,
          "same-width order conflict aborts the whole batch")

    // 另一种实测形态:主屏只有 4 个空名系统项(WiFi/Battery/BentoBox/Clock),名字落在副屏
    let emptyR = [StatusWindow(number: 1136, x: 1136, width: 38,  name: ""),
                  StatusWindow(number: 1174, x: 1174, width: 71,  name: ""),
                  StatusWindow(number: 1321, x: 1321, width: 42,  name: ""),
                  StatusWindow(number: 1363, x: 1363, width: 151, name: "")]
    let sysD = [StatusWindow(number: 3054, x: 3054, width: 38,  name: "WiFi"),
                StatusWindow(number: 3092, x: 3092, width: 71,  name: "Battery"),
                StatusWindow(number: 3239, x: 3239, width: 42,  name: "BentoBox-0"),
                StatusWindow(number: 3281, x: 3281, width: 151, name: "Clock")]
    let sysMapped = StatusItemPairing.crossScreenNames(recipients: emptyR, donors: sysD)
    checkEq(sysMapped.count, 4, "system items get named from the other screen's copy")
    checkEq(sysMapped[1174] ?? "", "Battery", "unique width 71 pins Battery")
    checkEq(sysMapped[1363] ?? "", "Clock", "unique width 151 pins Clock")

    // 位置键对齐的宽度自检:已知宽度不符即否决;未观测到的域跳过
    let w32 = StatusWindow(number: 7, x: 918, width: 32, name: "Item-0")
    check(StatusItemPairing.widthsConsistent([(w32, "com.tencent.qq")], knownWidths: ["com.tencent.qq": 32]),
          "known width agrees with the window")
    check(!StatusItemPairing.widthsConsistent([(w32, "com.tencent.xinWeChat")], knownWidths: ["com.tencent.xinwechat": 38]),
          "stale position key with wrong width is rejected")
    check(StatusItemPairing.widthsConsistent([(w32, "com.aiproxy.menubar")], knownWidths: [:]),
          "unobserved width is skipped, not rejected")
}

// 菜单图标「悬停也看得见」:判定单色图标 → 交给 AppKit 按菜单文字色重绘(模板图)
do {
    check(IconContrast.isNeutralPixel(r: 1, g: 1, b: 1), "pure white counts as neutral")
    check(IconContrast.isNeutralPixel(r: 0, g: 0, b: 0), "pure black counts as neutral")
    check(IconContrast.isNeutralPixel(r: 0.5, g: 0.5, b: 0.53), "near-gray counts as neutral")
    check(!IconContrast.isNeutralPixel(r: 1, g: 0.6, b: 0), "orange is not neutral")
    check(!IconContrast.isNeutralPixel(r: 0.2, g: 0.8, b: 0.3), "green is not neutral")

    func makeRGBA(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage? {
        guard let p = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: p, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    // 白/黑/彩色/透明 四类像素,统计灰阶占比(全透明像素不参与)
    let mixedPx: [UInt8] = [
        255, 255, 255, 255,   // 不透明白(深色菜单栏的典型产物)
        0, 0, 0, 255,         // 不透明黑(浅色菜单栏的产物)
        0, 0, 0, 0,           // 全透明
        255, 153, 0, 255,     // 不透明橙 → 唯一的彩色像素
    ]
    if let src = makeRGBA(mixedPx, 4, 1) {
        let ratio = IconContrast.neutralRatio(of: src)
        check(abs(ratio - 2.0 / 3.0) < 0.001, "neutral ratio counts 2 of 3 opaque pixels (got \(ratio))")
        // 三分之一的像素带彩色 → 不够格当模板图(彩色 logo 会被压成剪影)
        check(!IconContrast.isMonochrome(src), "one third colored pixels is not enough for template")
    } else {
        check(false, "failed to build mixed test bitmap")
    }
    // 真实状态项图标:整块内容都是同一族灰阶(偶尔一两个彩色角标) → 当模板图
    var glyphPx = [UInt8]()
    for _ in 0..<19 { glyphPx += [255, 255, 255, 255] }   // 19 个近白像素(深色菜单栏)
    glyphPx += [255, 153, 0, 255]                         // 1 个彩色角标
    if let src = makeRGBA(glyphPx, 20, 1) {
        check(IconContrast.neutralRatio(of: src) >= IconContrast.defaultNeutralRatio,
              "glyph with a single colored pixel is neutral enough")
        check(IconContrast.isMonochrome(src), "black/white glyph is treated as template")
    } else {
        check(false, "failed to build glyph test bitmap")
    }
    // 彩色占比够高就不该当模板图 —— 否则品牌 logo 会被压成单色剪影
    let coloredPx: [UInt8] = [
        255, 60, 0, 255,
        0, 200, 90, 255,
        40, 90, 255, 255,
        255, 255, 255, 255,
    ]
    if let src = makeRGBA(coloredPx, 4, 1) {
        check(!IconContrast.isMonochrome(src), "colorful app icon is not treated as template")
    } else {
        check(false, "failed to build colored test bitmap")
    }
    // 全透明 → 没有内容,不能判成模板图
    if let src = makeRGBA([0, 0, 0, 0, 0, 0, 0, 0], 2, 1) {
        checkEq(IconContrast.neutralRatio(of: src), 0, "fully transparent image has zero neutral ratio")
        check(!IconContrast.isMonochrome(src), "fully transparent image is not a template candidate")
    } else {
        check(false, "failed to build empty test bitmap")
    }
    checkEq(IconContrast.neutralRatio(of: makeRGBA([1, 2, 3, 4], 0, 0) ?? makeRGBA([1, 2, 3, 4], 1, 1)!),
            0, "degenerate image yields zero neutral ratio")
}

// 收纳菜单的自绘行:所有行必须同宽,否则菜单里文字参差不齐
do {
    // 纯图标行(草稿里的"暂无"占位也是这种)只有下限宽度
    checkEq(MenuRowLayout.unifiedWidth(widestTitle: 0),
            MenuRowLayout.defaultMinimumWidth,
            "icon only row falls back to the minimum width")
    checkEq(MenuRowLayout.unifiedWidth(widestTitle: 10),
            MenuRowLayout.defaultMinimumWidth,
            "narrow title still gets the minimum width")
    // 文字够宽时,行宽 = 前缀(图标左内边距+图标+间隙) + 最宽文字 + 右侧留白
    checkEq(MenuRowLayout.unifiedWidth(widestTitle: 200),
            MenuRowLayout.titleOriginX + 200 + MenuRowLayout.trailingInset,
            "wide title drives the row width")
    // 超长文字被上限截断,菜单不至于横穿屏幕
    checkEq(MenuRowLayout.unifiedWidth(widestTitle: 5000),
            MenuRowLayout.defaultMaximumWidth,
            "very long title is clamped to the maximum width")
    checkEq(MenuRowLayout.titleOriginX,
            MenuRowLayout.iconLeading + MenuRowLayout.iconSide + MenuRowLayout.titleGap,
            "title origin accounts for the icon column")
    // 「大图标 + 应用名」的观感:图标要完整落在行内还留呼吸位,文字明显小于图标
    check(MenuRowLayout.rowHeight >= MenuRowLayout.iconSide + 8,
          "icon fits inside the row with breathing room")
    check(MenuRowLayout.titleFontSize < MenuRowLayout.iconSide,
          "title stays smaller than the icon")
}

print("\n=== Result: \(passed) passed, \(failed) failed ===")
if failed>0 { exit(1) }
