import Foundation
import CoreGraphics

/// Phase values the Dock expects in a desktop-swipe gesture.
enum SwipePhase: UInt32 { case began = 1, changed = 2, ended = 4, cancelled = 8 }

struct SwipeOutput: Equatable {
    var phase: SwipePhase
    var progress: Double
    var velocity: Double = 0
}

/// Turns wheel input into a desktop-swipe gesture.
///
/// `goal` is where the wheel asked the gesture to be (1.0 = one desktop); `shown` trails it with a
/// first-order lag so the Dock animation stays smooth. Each time `shown` reaches a whole desktop the
/// gesture ends there and, if the wheel asked for more, a new gesture starts from zero.
struct SwipeState {
    /// Wheel notches closer than this belong to the same roll.
    static let flickGap = 0.3
    /// Lag of the shown position behind the goal.
    static let lag = 0.08
    /// Idle time after the last notch before a partial gesture settles and ends.
    static let settleDelay = 0.5

    private enum Mode { case idle, steps, roll }

    private var mode = Mode.idle
    private var goal = 0.0
    private var shown = 0.0
    private var announced = false
    private var lastTick = 0.0
    private var lastNotch = 0.0
    private var lastRollNotch = -Double.infinity

    var isActive: Bool { mode != .idle }

    static func clampSteps(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 2), 500) : 12
    }

    /// Gradual mode: the gesture follows the wheel; `delta` is in desktops.
    mutating func move(by delta: Double, at time: Double) {
        guard delta.isFinite, delta != 0 else { return }
        if mode == .idle { start(.steps, goal: 0, at: time) }
        lastNotch = time
        goal = min(max(goal + delta, -100), 100)
    }

    /// One roll of the wheel switches exactly one desktop, like a trackpad swipe.
    /// Notches during the roll or the animation are absorbed; a pause of ``flickGap`` starts a new roll.
    mutating func flick(_ delta: Double, at time: Double) {
        guard delta.isFinite, delta != 0 else { return }
        let startsRoll = mode == .idle && time - lastRollNotch >= Self.flickGap
        lastRollNotch = time
        guard startsRoll else { return }
        // Slightly past one desktop, so the lag crosses it in about 0.25 s instead of creeping up to it.
        start(.roll, goal: delta > 0 ? 1.05 : -1.05, at: time)
    }

    mutating func frame(at time: Double) -> [SwipeOutput] {
        guard mode != .idle else { return [] }
        let dt = min(max(time - lastTick, 0), 0.1)
        lastTick = time
        let before = shown
        shown += (goal - shown) * (1 - exp(-dt / Self.lag))
        if abs(goal - shown) < 0.0001 { shown = goal }

        var outputs: [SwipeOutput] = []
        if shown != before || (!announced && shown != 0) {
            outputs.append(SwipeOutput(phase: announced ? .changed : .began, progress: min(max(shown, -1), 1)))
            announced = true
        }
        if announced, abs(shown) >= 1 {
            let whole: Double = shown > 0 ? 1 : -1
            outputs.append(SwipeOutput(phase: .ended, progress: whole))
            announced = false
            shown = 0
            if mode == .roll {
                mode = .idle
                goal = 0
            } else {
                goal -= whole
            }
            return outputs
        }
        if time - lastNotch >= Self.settleDelay, shown == goal {
            if announced { outputs.append(SwipeOutput(phase: .ended, progress: shown)) }
            mode = .idle
            announced = false
        }
        return outputs
    }

    mutating func cancel() -> [SwipeOutput] {
        let outputs = announced ? [SwipeOutput(phase: .cancelled, progress: shown)] : []
        self = SwipeState()
        return outputs
    }

    private mutating func start(_ newMode: Mode, goal newGoal: Double, at time: Double) {
        mode = newMode
        goal = newGoal
        shown = 0
        announced = false
        lastTick = time
        lastNotch = time
    }
}

struct WheelInput {
    var horizontal: Double
    var vertical: Double
    var rawHorizontal: Double = 0
    var phase: Int64 = 0
    var momentum: Int64 = 0
    var synthetic = false

    func steps(capable: Bool) -> Double? {
        // Wheel mice only: trackpads and touch-surface mice scroll with phases/momentum; other apps' events are synthetic.
        guard capable, !synthetic,
              phase == 0, momentum == 0, vertical == 0,
              horizontal.isFinite, horizontal != 0 else { return nil }
        let magnitude = rawHorizontal.isFinite && rawHorizontal != 0 ? abs(rawHorizontal) : abs(horizontal)
        return horizontal > 0 ? magnitude : -magnitude
    }
}

struct SwipeEndRetryState {
    private(set) var pending: SwipeOutput?
    mutating func observe(_ output: SwipeOutput) -> Bool {
        switch output.phase {
        case .ended: pending = output
        case .began, .cancelled: pending = nil
        case .changed: return false
        }
        return true
    }
    mutating func cancel() { pending = nil }
}

struct MouseCaptureState {
    private(set) var isEnabled = false
    private var hadTarget = false
    private var waitingForAccessibility = false
    var endRetry = SwipeEndRetryState()
    var vertical = VerticalScrollState()
    var horizontal = VerticalScrollState()

    mutating func enable(targetConnected: Bool) {
        isEnabled = true
        hadTarget = targetConnected
        waitingForAccessibility = false
    }

    mutating func pause() {
        isEnabled = false
        hadTarget = false
        endRetry.cancel()
        vertical.cancel()
        horizontal.cancel()
    }

    mutating func observeTarget(connected: Bool) -> Bool {
        guard isEnabled else { return false }
        let disconnected = hadTarget && !connected
        hadTarget = connected
        if disconnected { pause() }
        return disconnected
    }
}

struct VerticalScrollState {
    private(set) var isActive = false
    private var pendingPixels = 0.0
    private var fractionalPixels = 0.0
    private var lastFrame = 0.0
    var residualPixels: Double { pendingPixels + fractionalPixels }

    static func clampSpeed(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0.1), 1) : 0.1
    }

    mutating func move(pixels: Double, speed: Double, at time: Double) -> Bool {
        let scaled = pixels * Self.clampSpeed(speed)
        guard scaled.isFinite, scaled != 0,
              abs(pendingPixels + scaled) < Double(Int32.max) else { return false }
        if !isActive { lastFrame = time }
        pendingPixels += scaled
        isActive = true
        return true
    }

    mutating func frame(at time: Double) -> Int32 {
        guard isActive else { return 0 }
        let elapsed = min(max(time - lastFrame, 0), 0.1)
        lastFrame = time
        var step = pendingPixels * (1 - exp(-elapsed / 0.08))
        if abs(pendingPixels - step) < 0.001 { step = pendingPixels }
        pendingPixels -= step
        fractionalPixels += step
        // Pixel events use integers; retain subpixels across idle wheel inputs.
        let pixels = Int32((fractionalPixels + (fractionalPixels >= 0 ? 1e-9 : -1e-9)).rounded(.towardZero))
        fractionalPixels -= Double(pixels)
        if abs(fractionalPixels) < 1e-9 { fractionalPixels = 0 }
        isActive = pendingPixels != 0
        return pixels
    }

    mutating func cancel() { self = VerticalScrollState() }
}

extension WheelInput {
    func verticalPixels(capable: Bool) -> Double? {
        guard capable, !synthetic,
              phase == 0, momentum == 0, horizontal == 0, rawHorizontal == 0,
              vertical.isFinite, vertical != 0 else { return nil }
        return vertical
    }
}

struct VerticalScrollMetadata {
    // This field backs AppKit's public isDirectionInvertedFromDevice property.
    static let inversionField = CGEventField(rawValue: 137)!
    var flags: CGEventFlags
    var invertedFromDevice: Int64

    init(event: CGEvent) {
        flags = event.flags
        invertedFromDevice = event.getIntegerValueField(Self.inversionField)
    }

    func isCompatible(with other: Self) -> Bool {
        flags == other.flags && invertedFromDevice == other.invertedFromDevice
    }

    /// `horizontal` fills the second wheel axis; smoothing state is axis-agnostic.
    func makeEvent(pixels: Int32, horizontal: Int32 = 0) -> CGEvent? {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: horizontal != 0 ? 2 : 1,
                                  wheel1: pixels, wheel2: horizontal, wheel3: 0) else { return nil }
        // Location stays at the current cursor (the default): smoothing frames keep posting
        // after the wheel stops, and a stored position would pull the pointer back.
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: 0x4d455341)
        event.setIntegerValueField(Self.inversionField, value: invertedFromDevice)
        return event
    }
}

struct MousePermissionState {
    var accessibility: Bool
    var inputMonitoring: Bool
    var eventPosting: Bool
    // A modifying defaultTap uses Accessibility; listen-only monitoring is separate.
    var canAttemptCapture: Bool { accessibility }
    var pausedStatus: String {
        accessibility ? L("Paused — Accessibility granted; turn Horizon Mouse on") :
            L("Accessibility not recognized for this process. Check Horizon Mouse in Accessibility and reopen the app.")
    }
    var tapFailureStatus: String {
        accessibility ? L("Accessibility granted, but capture didn't start. Quit and reopen Horizon Mouse; check this app's entry in Accessibility.") : pausedStatus
    }
}

extension MouseCaptureState {
    mutating func updatePermissions(_ permission: MousePermissionState) -> String? {
        guard !isEnabled else { return nil }
        let updateStatus = !permission.canAttemptCapture || waitingForAccessibility
        waitingForAccessibility = !permission.canAttemptCapture
        return updateStatus ? permission.pausedStatus : nil
    }
}
