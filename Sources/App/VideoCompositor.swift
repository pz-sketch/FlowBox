import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import SharedCore

struct PipLayout: Equatable {
    let x: CGFloat
    let y: CGFloat
    let w: Int
    let h: Int
}

enum VideoCompositor {

    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    static func pipLayout(for cfg: RecordingConfig, outputW: Int, outputH: Int, scale: CGFloat) -> PipLayout {
        let isCircle = cfg.cameraIsCircle
        let pipWpt = max(120, min(360, cfg.cameraWidth))
        let pipW = Int(pipWpt * scale)
        let pipH = isCircle ? pipW : pipW * 9 / 16
        let margin: CGFloat = 16 * scale
        var pipX: CGFloat
        var pipY: CGFloat
        if cfg.cameraX < 0 || cfg.cameraY < 0 {
            pipX = CGFloat(outputW) - CGFloat(pipW) - margin
            pipY = margin
        } else {
            let nx = min(1, max(0, cfg.cameraX))
            let ny = min(1, max(0, cfg.cameraY))
            pipX = nx * CGFloat(outputW - pipW)
            pipY = ny * CGFloat(outputH - pipH)
        }
        pipX = min(max(0, pipX), CGFloat(outputW - pipW))
        pipY = min(max(0, pipY), CGFloat(outputH - pipH))
        return PipLayout(x: pipX, y: pipY, w: pipW, h: pipH)
    }

    static func scaleAndCrop(camW: CGFloat, camH: CGFloat, pipW: Int, pipH: Int) -> (scale: CGFloat, cropX: CGFloat, cropY: CGFloat) {
        let sx = CGFloat(pipW) / camW
        let sy = CGFloat(pipH) / camH
        let s = max(sx, sy)
        let scaledW = camW * s
        let scaledH = camH * s
        let cropX = (scaledW - CGFloat(pipW)) / 2
        let cropY = (scaledH - CGFloat(pipH)) / 2
        return (s, cropX, cropY)
    }

    static func compositedPixelBuffer(
        srcPixelBuffer: CVPixelBuffer,
        camPixelBuffer: CVPixelBuffer,
        config cfg: RecordingConfig,
        outputW: Int,
        outputH: Int,
        scale: CGFloat
    ) -> CVPixelBuffer? {
        let layout = pipLayout(for: cfg, outputW: outputW, outputH: outputH, scale: scale)
        let camW = CGFloat(CVPixelBufferGetWidth(camPixelBuffer))
        let camH = CGFloat(CVPixelBufferGetHeight(camPixelBuffer))
        if camW < 1 || camH < 1 { return nil }

        var ciCam = CIImage(cvPixelBuffer: camPixelBuffer)
        let (s, cropX, cropY) = scaleAndCrop(camW: camW, camH: camH, pipW: layout.w, pipH: layout.h)
        ciCam = ciCam.transformed(by: CGAffineTransform(scaleX: s, y: s))
        ciCam = ciCam.cropped(to: CGRect(x: cropX, y: cropY, width: CGFloat(layout.w), height: CGFloat(layout.h)))
        ciCam = ciCam.transformed(by: CGAffineTransform(translationX: layout.x - cropX, y: layout.y - cropY))

        let ciSrc = CIImage(cvPixelBuffer: srcPixelBuffer)

        if cfg.cameraIsCircle {
            let radius = CGFloat(min(layout.w, layout.h)) / 2
            let center = CGPoint(x: layout.x + CGFloat(layout.w) / 2, y: layout.y + CGFloat(layout.h) / 2)
            let radialParams: [String: Any] = [
                kCIInputCenterKey: CIVector(cgPoint: center),
                "inputRadius0": radius,
                "inputRadius1": radius + 1,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
                "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 1),
            ]
            if let radial = CIFilter(name: "CIRadialGradient", parameters: radialParams),
               let radialOut = radial.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: CGFloat(outputW), height: CGFloat(outputH))) {
                if let blend = CIFilter(name: "CIBlendWithMask") {
                    blend.setValue(ciCam, forKey: kCIInputImageKey)
                    blend.setValue(CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: CGRect(x: 0, y: 0, width: CGFloat(outputW), height: CGFloat(outputH))), forKey: kCIInputBackgroundImageKey)
                    blend.setValue(radialOut, forKey: kCIInputMaskImageKey)
                    if let masked = blend.outputImage {
                        ciCam = masked
                    }
                }
            }
        }

        let composed: CIImage
        if cfg.cameraIsCircle {
            composed = ciCam.composited(over: ciSrc)
        } else {
            let borderRect = CGRect(x: layout.x - 2, y: layout.y - 2, width: CGFloat(layout.w) + 4, height: CGFloat(layout.h) + 4)
            let border = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: borderRect)
            let bg = border.composited(over: ciSrc)
            composed = ciCam.composited(over: bg)
        }

        var newPB: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let status = CVPixelBufferCreate(kCFAllocatorDefault, outputW, outputH, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &newPB)
        guard status == kCVReturnSuccess, let outPB = newPB else { return nil }
        ciContext.render(composed, to: outPB)
        return outPB
    }

    static func newSampleBuffer(from pixelBuffer: CVPixelBuffer, timing: CMSampleTimingInfo) -> CMSampleBuffer? {
        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &fmt)
        guard let fmt else { return nil }
        var sample: CMSampleBuffer?
        var timingInfo = timing
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: fmt,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sample
        )
        guard status == noErr else { return nil }
        return sample
    }
}
