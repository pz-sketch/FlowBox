import CoreGraphics
import Foundation

/// 截图选区拖动的纯计算部分:把「鼠标位移」换算成「选区实际位移」并夹在屏幕内。
///
/// 标注笔画与选区共用同一套绝对坐标(导出时按选区原点平移裁切),
/// 因此两者必须用同一个 delta 平移,相对位置才不会错开。
/// 这里不依赖 AppKit,便于单测覆盖。
public enum SelectionGeometry {

    /// 把期望位移夹到边界内,使 `rect` 平移后完整落在 `bounds` 里。
    ///
    /// - 正常情况:`rect` 小于 `bounds`,返回落在 [minDelta, maxDelta] 内的位移。
    /// - 退化情况:`rect` 比 `bounds` 还大(理论上不该出现),无法完全容纳,
    ///   此时返回零位移而不是乱滑,避免选区被推出屏幕。
    public static func clampedDelta(rect: CGRect, bounds: CGRect, dx: CGFloat, dy: CGFloat) -> CGPoint {
        let minDX = bounds.minX - rect.minX
        let maxDX = bounds.maxX - rect.maxX
        let minDY = bounds.minY - rect.minY
        let maxDY = bounds.maxY - rect.maxY
        let x = minDX <= maxDX ? min(max(dx, minDX), maxDX) : 0
        let y = minDY <= maxDY ? min(max(dy, minDY), maxDY) : 0
        return CGPoint(x: x, y: y)
    }

    /// 按位移整体平移矩形
    public static func offset(_ rect: CGRect, by delta: CGPoint) -> CGRect {
        rect.offsetBy(dx: delta.x, dy: delta.y)
    }

    /// 按同一位移平移一组点(标注顶点),保持与选区的相对位置
    public static func offset(_ points: [CGPoint], by delta: CGPoint) -> [CGPoint] {
        guard delta.x != 0 || delta.y != 0 else { return points }
        return points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
    }
}
