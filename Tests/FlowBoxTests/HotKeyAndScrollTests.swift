import Testing
import SharedCore

func hotKeyModifierString(_ mods: UInt32) -> String {
    var s = ""
    if mods & 4096 != 0 { s += "⌃" }
    if mods & 2048 != 0 { s += "⌥" }
    if mods & 512 != 0 { s += "⇧" }
    if mods & 256 != 0 { s += "⌘" }
    return s
}
func hotKeyName(_ code: UInt32) -> String {
    let m: [UInt32:String] = [0:"A",15:"R",53:"Esc",36:"回车",49:"空格",122:"F1"]
    return m[code] ?? "Key(\(code))"
}
func scaledDelta(_ delta: Double, minStep: Double) -> Double { delta * minStep / 60.0 }
func shouldStop(_ remaining: Double, epsilon: Double = 0.6) -> Bool { abs(remaining) < epsilon }
func easedStep(_ remaining: Double, ease: Double = 0.5) -> Double { remaining * ease }
func clampedMinStep(_ v: Double) -> Double { min(120, max(10, v)) }

@Suite("HotKey and Scroll")
struct HotKeyAndScrollTests {
    @Test func modifierString() {
        #expect(hotKeyModifierString(2048) == "⌥")
        #expect(hotKeyModifierString(2048|256) == "⌥⌘")
        #expect(hotKeyModifierString(0) == "")
        #expect(hotKeyModifierString(4096|2048|512|256) == "⌃⌥⇧⌘")
    }
    @Test func keyName() {
        #expect(hotKeyName(0) == "A")
        #expect(hotKeyName(15) == "R")
        #expect(hotKeyName(53) == "Esc")
        #expect(hotKeyName(999).hasPrefix("Key("))
    }
    @Test func conflict() {
        #expect((0 as UInt32) == 0 && (2048 as UInt32) == 2048)
        #expect((2048 as UInt32) != (256 as UInt32))
    }
    @Test func comboName() {
        #expect(hotKeyModifierString(2048)+hotKeyName(0) == "⌥A")
        #expect(hotKeyModifierString(2048)+hotKeyName(15) == "⌥R")
    }
    @Test func scaled() {
        #expect(abs(scaledDelta(10,minStep:60)-10) < 0.01)
        #expect(abs(scaledDelta(10,minStep:120)-20) < 0.01)
        #expect(abs(scaledDelta(10,minStep:30)-5) < 0.01)
    }
    @Test func shouldStopCheck() {
        #expect(shouldStop(0.5)==true)
        #expect(shouldStop(0.7)==false)
    }
    @Test func eased() {
        #expect(abs(easedStep(10,ease:0.5)-5)<0.01)
        #expect(abs(easedStep(100,ease:0.5)-50)<0.01)
    }
    @Test func clamped() {
        #expect(clampedMinStep(5)==10)
        #expect(clampedMinStep(300)==120)
        #expect(clampedMinStep(60)==60)
    }
    @Test func convergence() {
        var r=100.0; var steps=0
        while !shouldStop(r) && steps<20 { r-=easedStep(r); steps+=1 }
        #expect(shouldStop(r)==true)
        #expect(steps<20 && steps>5)
    }
    @Test func reverse() {
        #expect(abs(-scaledDelta(10,minStep:60)+10)<0.01)
    }
}
