import ApplicationServices
import CoreGraphics
import os
import Foundation

/// 诊断用:记录前几条滚轮事件的字段,便于排查不同鼠标的事件形态
private var scrollEventLogCount = 0

/// 重发事件的自定义标记(防止重发的事件再次进入拦截形成循环)
private let repostMarker: Int64 = 0x5250_4358

/// 诊断日志直接写文件(未签名进程的 NSLog 进不了系统日志)
private func debugLog(_ message: String) {
    FlowLog.scroll.debug("\(message, privacy: .public)")
    let url = URL(fileURLWithPath: "/tmp/flowbox-scroll-debug.log")
    let line = "\(Date()) \(message)\n"
    if let data = line.data(using: .utf8) {
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

/// 滚轮处理引擎:
/// - 反转:丢弃离散事件,重发翻转后的新事件(macOS 26 原地修改硬件事件不生效)
/// - 平滑:吞掉离散事件,把像素量累积为"目标值",由 ~140Hz 定时器按指数缓动
///   持续发出连续(continuous)滚动事件,得到触控板般的流畅滚动;滑完自动停。
/// 触控板事件本身是连续的,两条路径都直接放行。
/// 修改/重发事件需要「辅助功能」权限,tap 创建失败即未授权。
final class ScrollReverser {

    static let shared = ScrollReverser()

    // 运行参数(设置变更时从外部同步)
    var reverseEnabled = false
    var smoothEnabled = false
    /// 最短步长,60 为中性(输入像素 × minStep/60)
    var minStep: Double = 60

    private var eventTap: CFMachPort?
    private var thread: Thread?

    // 平滑状态(仅在 queue 上访问)
    private let queue = DispatchQueue(label: "net.ai2048.flowbox.scroll")
    private var remaining: [Double] = [0, 0]  // [垂直 y, 水平 x] 待滑出的像素
    private var animatorRunning = false
    private let ease: Double = 0.5            // 每帧向目标靠近的比例(帧 ~7ms);越大起步越跟手
    private let epsilon: Double = 0.6         // 少于该值视为到达,避免无限小步与零像素事件

    // MARK: - Testable helpers
    static func scaledDelta(_ delta: Double, minStep: Double) -> Double {
        delta * minStep / 60.0
    }

    static func shouldStop(remaining: Double, epsilon: Double = 0.6) -> Bool {
        abs(remaining) < epsilon
    }

    static func easedStep(remaining: Double, ease: Double = 0.5) -> Double {
        remaining * ease
    }

    static func clampedMinStep(_ value: Double) -> Double {
        min(120, max(10, value))
    }

    func currentRemaining() -> [Double] {
        var r: [Double] = [0,0]
        queue.sync { r = self.remaining }
        return r
    }

    private init() {}

    /// 是否正在运行
    var isRunning: Bool { eventTap != nil }

    /// 启动拦截;返回 false 表示没有辅助功能权限(tap 创建失败)
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, _ -> Unmanaged<CGEvent>? in
                ScrollReverser.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: nil
        ) else {
            debugLog("创建滚轮事件拦截失败(缺少辅助功能权限?)")
            // 让系统弹出授权引导(把当前签名正确写入 TCC)
            _ = PermissionManager.requestAccessibilityPrompt()
            return false
        }

        eventTap = tap
        thread = Thread { [weak self, tap] in
            guard let self = self else { return }
            let mode = CFRunLoopMode.commonModes.rawValue
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                return
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        thread?.name = "FlowBox.ScrollEngine"
        thread?.start()
        debugLog("滚轮引擎已启动 reverse=\(reverseEnabled) smooth=\(smoothEnabled)")
        return true
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        eventTap = nil
        queue.async { [weak self] in
            self?.remaining = [0, 0]
            self?.animatorRunning = false
        }
        thread = nil
        debugLog("滚轮引擎已停止")
    }

    // MARK: - 事件回调(tap 线程)

    fileprivate static func handleEvent(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        let s = ScrollReverser.shared

        // tap 被系统超时禁用时自动重启
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let tapPort = Unmanaged<CFMachPort>.fromOpaque(UnsafeRawPointer(proxy))
                .takeUnretainedValue()
            CGEvent.tapEnable(tap: tapPort, enable: true)
            return Unmanaged.passUnretained(event)
        }

        // 自己发出的事件直接放行,避免循环
        if event.getIntegerValueField(.eventSourceUserData) == repostMarker {
            return Unmanaged.passUnretained(event)
        }

        // 触控板(含惯性)是连续事件,直接放行
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            return Unmanaged.passUnretained(event)
        }

        let pointY = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        let pointX = Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
        let lineY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        let lineX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))

        // 距离以"格数"为基准:每格 = minStep 像素,与驱动快慢滚的像素爬坡解耦,
        // 保证轻滚一格也有明确可感的距离;无格信息时退回按像素缩放
        func distance(line: Double, point: Double) -> Double {
            let sign: Double = s.reverseEnabled ? -1 : 1
            if line != 0 {
                return line * s.minStep * sign
            }
            return point * (s.minStep / 60.0) * sign
        }

        if scrollEventLogCount < 8 {
            scrollEventLogCount += 1
            debugLog("输入事件#\(scrollEventLogCount) 格y=\(lineY) 像素y=\(pointY) smooth=\(s.smoothEnabled)")
        }

        // 平滑模式:吞掉离散事件,累积进动画目标
        if s.smoothEnabled {
            s.queue.async {
                s.remaining[0] += distance(line: lineY, point: pointY)
                s.remaining[1] += distance(line: lineX, point: pointX)
                s.ensureAnimator()
            }
            return nil
        }

        // 仅反转模式:丢弃原事件,重发翻转副本
        if s.reverseEnabled {
            if let flipped = event.copy() {
                for field in [
                    CGEventField.scrollWheelEventDeltaAxis1,
                    CGEventField.scrollWheelEventPointDeltaAxis1,
                    CGEventField.scrollWheelEventFixedPtDeltaAxis1,
                    CGEventField.scrollWheelEventDeltaAxis2,
                    CGEventField.scrollWheelEventPointDeltaAxis2,
                    CGEventField.scrollWheelEventFixedPtDeltaAxis2,
                ] {
                    flipped.setIntegerValueField(field, value: -event.getIntegerValueField(field))
                }
                flipped.setIntegerValueField(.eventSourceUserData, value: repostMarker)
                flipped.post(tap: .cgSessionEventTap)
                return nil
            }
        }

        // 什么都没开启:原样放行
        return Unmanaged.passUnretained(event)
    }

    // MARK: - 平滑动画器(queue 上)

    /// 有待滑出像素时启动帧定时器
    private func ensureAnimator() {
        guard !animatorRunning else { return }
        animatorRunning = true
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .milliseconds(7), leeway: .milliseconds(1))
        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.animationTick()
        }
        source.resume()
        // 引用保存在队列上下文外的属性,stop 时 cancel
        animatorSource = source
    }

    private var animatorSource: DispatchSourceTimer?

    private func animationTick() {
        for axis in 0...1 {
            let r = remaining[axis]
            guard abs(r) > epsilon else {
                remaining[axis] = 0
                continue
            }
            var inc = r * ease
            // 防止最后一帧过冲
            if abs(inc) > abs(r) || abs(inc) < epsilon / 2 {
                inc = abs(r) <= epsilon ? r : (r > 0 ? min(abs(r), epsilon * 4) : -min(abs(r), epsilon * 4))
            }
            postContinuous(dy: axis == 0 ? inc : 0, dx: axis == 1 ? inc : 0)
            remaining[axis] = r - inc
        }
        // 全部滑完 → 停止帧定时器
        if abs(remaining[0]) <= epsilon && abs(remaining[1]) <= epsilon {
            remaining = [0, 0]
            animatorRunning = false
            animatorSource?.cancel()
            animatorSource = nil
        }
    }

    /// 发出一条平滑(连续)滚动事件,带自标记防止被自己再次处理
    private func postContinuous(dy: Double, dx: Double) {
        guard dy != 0 || dx != 0, let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: dy != 0 ? 1 : 2,
            wheel1: Int32(clamping: Int(dy)),
            wheel2: Int32(clamping: Int(dx)),
            wheel3: 0
        ) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        // 连续事件的精确量放在 Point/FixedPt 字段
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: dy)
        if dx != 0 {
            event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: dx)
        }
        event.setIntegerValueField(.eventSourceUserData, value: repostMarker)
        event.post(tap: .cgSessionEventTap)
    }
}
