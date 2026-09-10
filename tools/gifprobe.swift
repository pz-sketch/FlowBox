// 录屏转 GIF 编码路径端到端探针:
// 合成测试视频 → 按 GifEncodePlan 抽帧缩放 → ImageIO 写 GIF → 校验产物。
//
// 运行(多文件时顶层代码必须落在 main.swift,直接 `swift a.swift b.swift` 会找不到符号):
//   mkdir -p /tmp/gife2e && cp tools/gifprobe.swift /tmp/gife2e/main.swift
//   swiftc -O -o /tmp/gife2e/run /tmp/gife2e/main.swift Sources/SharedCore/GifPlan.swift
//   /tmp/gife2e/run
import AVFoundation
import CoreGraphics
import CoreVideo
import CoreMedia
import ImageIO
import UniformTypeIdentifiers
import Foundation

var passed = 0, failed = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { passed += 1; print("✅ \(msg)") }
    else { failed += 1; print("❌ \(msg)") }
}

let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gifprobe-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
let videoURL = dir.appendingPathComponent("probe.mov")
let gifURL = dir.appendingPathComponent("probe.gif")
defer { try? FileManager.default.removeItem(at: dir) }

// ---------- 1) 合成测试视频 640x360@30fps,2 秒,渐变色 + 移动方块 ----------
let W = 640, H = 360, FPS = 30, SECONDS = 2
let frameTotal = FPS * SECONDS

func makePixelBuffer(index: Int) -> CVPixelBuffer? {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, W, H, kCVPixelFormatType_32BGRA, nil, &pb)
    guard let buf = pb else { return nil }
    CVPixelBufferLockBaseAddress(buf, [])
    defer { CVPixelBufferUnlockBaseAddress(buf, []) }
    let base = CVPixelBufferGetBaseAddress(buf)!.assumingMemoryBound(to: UInt8.self)
    let stride = CVPixelBufferGetBytesPerRow(buf)
    let r = UInt8(truncatingIfNeeded: index * 23), g = UInt8(truncatingIfNeeded: index * 47), b = UInt8(truncatingIfNeeded: index * 11)
    for row in 0..<H {
        let line = base + row * stride
        for col in 0..<W {
            let p = line + col * 4
            p[0] = b; p[1] = g; p[2] = r; p[3] = 255
        }
    }
    // 移动白方块,保证帧间差异明显
    let sq = 40, sx = (index * 9) % (W - sq), sy = (index * 5) % (H - sq)
    for row in sy..<(sy + sq) {
        let line = base + row * stride + sx * 4
        for col in 0..<sq {
            line[col * 4] = 255; line[col * 4 + 1] = 255; line[col * 4 + 2] = 255; line[col * 4 + 3] = 255
        }
    }
    return buf
}

do {
    let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: W, AVVideoHeightKey: H,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: W,
        kCVPixelBufferHeightKey as String: H,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    let sem = DispatchSemaphore(value: 0)
    var i = 0
    input.requestMediaDataWhenReady(on: DispatchQueue(label: "probe")) {
        while input.isReadyForMoreMediaData, i < frameTotal {
            if let pb = makePixelBuffer(index: i) {
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(FPS)))
            }
            i += 1
        }
        if i >= frameTotal {
            input.markAsFinished()
            writer.finishWriting { sem.signal() }
        }
    }
    sem.wait()
    check(writer.status == .completed, "测试视频写入完成 status=\(writer.status.rawValue)")
} catch {
    check(false, "测试视频创建异常: \(error)")
    exit(1)
}

// ---------- 2) 按 GifEncodePlan 抽帧缩放,写 GIF(与 GifEncodeJob 相同的路径) ----------
guard let plan = GifEncodePlan(fps: 10, maxWidth: 320, sourceW: W, sourceH: H, duration: Double(SECONDS)) else {
    check(false, "GifEncodePlan 构建失败")
    exit(1)
}
check(plan.frameCount == 20, "plan frameCount=20 实际 \(plan.frameCount)")
check(plan.outW == 320 && plan.outH == 180, "plan 输出尺寸 320x180 实际 \(plan.outW)x\(plan.outH)")

let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, plan.frameCount, nil)
check(dest != nil, "CGImageDestination 创建")
guard let dest else { exit(1) }
CGImageDestinationSetProperties(dest, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
] as CFDictionary)

let gen = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero
gen.requestedTimeToleranceAfter = .zero
let times = plan.frameTimes.map { NSValue(time: CMTime(seconds: $0, preferredTimescale: 600)) }

let sem2 = DispatchSemaphore(value: 0)
let lock = NSLock()
var written = 0
var decodeFails = 0
gen.generateCGImagesAsynchronously(forTimes: times) { _, image, _, result, error in
    lock.lock()
    if case .succeeded = result, let image {
        let ctx = CGContext(
            data: nil, width: plan.outW, height: plan.outH,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: plan.outW, height: plan.outH))
        let scaled = ctx.makeImage()!
        CGImageDestinationAddImage(dest, scaled, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: Double(plan.delayCS) / 100.0],
        ] as CFDictionary)
        written += 1
    } else {
        decodeFails += 1
        print("   帧失败: \(String(describing: error))")
    }
    lock.unlock()
    sem2.signal()
}
for _ in 0..<plan.frameCount { sem2.wait() }
gen.cancelAllCGImageGeneration()
check(written == 20 && decodeFails == 0, "抽帧写入 20/20 实际 written=\(written) fail=\(decodeFails)")
let finalized = CGImageDestinationFinalize(dest)
check(finalized, "GIF finalize")
guard finalized else { exit(1) }

// ---------- 3) 校验 GIF 产物 ----------
let size = (try? FileManager.default.attributesOfItem(atPath: gifURL.path)[.size] as? Double) ?? 0
print("   GIF 大小: \(Int(size)) bytes")
check(size > 1000, "GIF 文件大小合理")

let magic = String(bytes: (try? Data(contentsOf: gifURL))?.prefix(6) ?? Data(), encoding: .ascii) ?? "?"
check(magic == "GIF87a" || magic == "GIF89a", "GIF 魔数 实际 \(magic)")

let src = CGImageSourceCreateWithURL(gifURL as CFURL, nil)
check(src != nil, "CGImageSource 可读")
guard let src else { exit(1) }
check(CGImageSourceGetCount(src) == 20, "GIF 帧数 20 实际 \(CGImageSourceGetCount(src))")

let gprops = CGImageSourceCopyProperties(src, nil) as? [String: Any]
let gdictTop = gprops?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
let pw = gdictTop?["CanvasPixelWidth"] as? Int ?? gprops?[kCGImagePropertyPixelWidth as String] as? Int ?? -1
let ph = gdictTop?["CanvasPixelHeight"] as? Int ?? gprops?[kCGImagePropertyPixelHeight as String] as? Int ?? -1
check(pw == 320 && ph == 180, "GIF 逻辑尺寸 320x180 实际 \(pw)x\(ph)")
let loop = gdictTop?[kCGImagePropertyGIFLoopCount as String] as? Int ?? -1
check(loop == 0, "GIF 无限循环 loop=0 实际 \(loop)")

let fprops = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any]
let delay = ((fprops?[kCGImagePropertyGIFDictionary as String] as? [String: Any])?[kCGImagePropertyGIFDelayTime as String] as? Double) ?? -1
check(abs(delay - 0.1) < 0.001, "GIF 帧延迟 0.1s 实际 \(delay)")

// 帧内容确实在动:首末帧中心像素不同(方块位置/底色随帧变化)
if let f0 = CGImageSourceCreateImageAtIndex(src, 0, nil),
   let f19 = CGImageSourceCreateImageAtIndex(src, 19, nil) {
    func centerColor(_ img: CGImage) -> (UInt8, UInt8, UInt8) {
        let w = img.width, h = img.height
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: CGFloat(-w / 2), y: CGFloat(-h / 2), width: CGFloat(w), height: CGFloat(h)))
        return (px[0], px[1], px[2])
    }
    let c0 = centerColor(f0), c19 = centerColor(f19)
    check(c0 != c19, "首末帧画面不同(动画有效) \(c0) vs \(c19)")
} else {
    check(false, "GIF 帧解码失败")
}

print("\n=== gifprobe: \(passed) passed, \(failed) failed ===")
if failed > 0 { exit(1) }
