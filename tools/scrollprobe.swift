import CoreGraphics
import Foundation

// 只听不改的探针:挂在会话层,看最终流向应用的事件(诊断用)
let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: mask,
    callback: { _, type, event, _ in
        if type == .scrollWheel {
            let d = event.getIntegerValueField(.scrollWheelEventDeltaAxis1)
            let p = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let c = event.getIntegerValueField(.scrollWheelEventIsContinuous)
            print("PROBE 行=\(d) 像素=\(String(format: "%.0f", p)) 连续=\(c)", terminator: " | ")
            fflush(stdout)
        }
        return Unmanaged.passUnretained(event)
    },
    userInfo: nil
) else {
    print("PROBE: tap 创建失败"); exit(1)
}
let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
print("PROBE 就绪", terminator: " ")
fflush(stdout)
CFRunLoopRunInMode(.defaultMode, 6, false)
print(" PROBE 结束")
