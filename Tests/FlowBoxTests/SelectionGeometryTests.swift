import Testing
import SharedCore
import CoreGraphics

@Suite("SelectionGeometry")
struct SelectionGeometryTests {

    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let rect = CGRect(x: 100, y: 100, width: 200, height: 150)

    @Test func deltaInRange() {
        let delta = SelectionGeometry.clampedDelta(rect: rect, bounds: bounds, dx: 50, dy: -30)
        #expect(delta == CGPoint(x: 50, y: -30))
        #expect(SelectionGeometry.offset(rect, by: delta) == CGRect(x: 150, y: 70, width: 200, height: 150))
    }

    @Test func deltaClampedAtEdges() {
        // 右/下极限: maxX 300 → 1000(可移 700), maxY 250 → 800(可移 550)
        #expect(SelectionGeometry.clampedDelta(rect: rect, bounds: bounds, dx: 9999, dy: 9999) == CGPoint(x: 700, y: 550))
        // 左/上极限: minX/minY 100 → 0(可移 -100)
        #expect(SelectionGeometry.clampedDelta(rect: rect, bounds: bounds, dx: -9999, dy: -9999) == CGPoint(x: -100, y: -100))
    }

    @Test func movedRectAlwaysInsideBounds() {
        let desires = [
            CGPoint(x: 9999, y: 9999), CGPoint(x: -9999, y: -9999),
            CGPoint(x: 500, y: -400), CGPoint(x: 12, y: 7),
        ]
        for d in desires {
            let delta = SelectionGeometry.clampedDelta(rect: rect, bounds: bounds, dx: d.x, dy: d.y)
            let moved = SelectionGeometry.offset(rect, by: delta)
            #expect(bounds.contains(moved))
            #expect(moved.size == rect.size)
        }
    }

    @Test func oversizedSelectionYieldsZeroDelta() {
        // 选区比屏幕还大时无法完全容纳,应保持不动而不是乱滑
        let huge = CGRect(x: -20, y: -20, width: 1200, height: 900)
        #expect(SelectionGeometry.clampedDelta(rect: huge, bounds: bounds, dx: 100, dy: 100) == .zero)
    }

    @Test func annotationPointsMoveWithSelection() {
        let points = [CGPoint(x: 120, y: 130), CGPoint(x: 260, y: 210)]
        let delta = CGPoint(x: 50, y: -30)
        let shifted = SelectionGeometry.offset(points, by: delta)
        #expect(shifted == [CGPoint(x: 170, y: 100), CGPoint(x: 310, y: 180)])
        // 与选区的相对位置保持不变(导出按选区原点裁切,错位就会画歪)
        let movedRect = SelectionGeometry.offset(rect, by: delta)
        for (before, after) in zip(points, shifted) {
            #expect(after.x - movedRect.minX == before.x - rect.minX)
            #expect(after.y - movedRect.minY == before.y - rect.minY)
        }
    }

    @Test func zeroDeltaKeepsPointsUntouched() {
        let points = [CGPoint(x: 120, y: 130)]
        #expect(SelectionGeometry.offset(points, by: .zero) == points)
    }
}
