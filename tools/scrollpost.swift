import CoreGraphics
import Foundation

// 合成注入离散滚轮事件:向下滚 3 格(诊断用)
for _ in 1...3 {
    if let ev = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0) {
        ev.post(tap: .cghidEventTap)
        usleep(200_000)
    }
}
print("POSTED")
