import Foundation
import AppKit
#if canImport(XCTest) && !MESA_MOUSE_SELF_CHECK
import XCTest
@testable import MouseKit
#else
// Command Line Tools omit XCTest; keep the same behavior checks runnable with swiftc.
class XCTestCase {}
private func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { assert(a == b, "expected \(b), got \(a)") }
private func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double) { assert(abs(a - b) <= accuracy) }
private func XCTAssertTrue(_ a: Bool) { assert(a) }
private func XCTAssertFalse(_ a: Bool) { assert(!a) }
private func XCTAssertNil<T>(_ a: T?) { assert(a == nil) }
private func XCTAssertLessThan(_ a: Double, _ b: Double) { assert(a < b) }
private func XCTAssertGreaterThan(_ a: Double, _ b: Double) { assert(a > b) }
#endif

final class MouseKitTests: XCTestCase {
    func testFiveHundredStepSwipeStillFollowsGradually() {
        for direction in [-1.0, 1.0] {
            var swipe = SwipeState()
            let delta = direction / 500
            swipe.move(by: delta, at: 0)
            var outputs = swipe.frame(at: 1.0 / 120)
            XCTAssertEqual(outputs.first?.phase, .began)
            XCTAssertGreaterThan(outputs.first!.progress * direction, 0)
            XCTAssertLessThan(outputs.first!.progress * direction, abs(delta))
            for tick in 2...59 { outputs += swipe.frame(at: Double(tick) / 120) }
            XCTAssertTrue(swipe.isActive)
            XCTAssertFalse(outputs.contains { $0.phase == .ended })
            var previous = 0.0
            for output in outputs {
                XCTAssertTrue(output.progress * direction >= previous)
                previous = output.progress * direction
            }
            outputs += swipe.frame(at: 0.501)
            XCTAssertEqual(outputs.last?.phase, .ended)
            XCTAssertEqual(outputs.last!.progress, delta, accuracy: 0.000000001)
            XCTAssertFalse(swipe.isActive)
        }
    }

    func testSlowNotchesStayInOneGestureUntilHalfSecondIdle() {
        var swipe = SwipeState()
        var outputs: [SwipeOutput] = []
        for notch in 0..<4 {
            let time = Double(notch) * 0.3
            swipe.move(by: 1.0 / 500, at: time)
            for tick in 1...35 { outputs += swipe.frame(at: time + Double(tick) / 120) }
            XCTAssertTrue(swipe.isActive)
            XCTAssertFalse(outputs.contains { $0.phase == .ended })
        }
        for tick in 36...59 { outputs += swipe.frame(at: 0.9 + Double(tick) / 120) }
        XCTAssertTrue(swipe.isActive)
        XCTAssertFalse(outputs.contains { $0.phase == .ended })
        XCTAssertEqual(outputs.filter { $0.phase == .began }.count, 1)
        outputs += swipe.frame(at: 1.41)
        XCTAssertEqual(outputs.last?.phase, .ended)
        XCTAssertEqual(outputs.last!.progress, 4.0 / 500, accuracy: 0.000000001)
        XCTAssertFalse(swipe.isActive)
    }

    func testEasingReversalAndIdleRelease() {
        var swipe = SwipeState()
        swipe.move(by: 0.75, at: 0)
        var outputs = swipe.frame(at: 1.0 / 120)
        XCTAssertEqual(outputs.first?.phase, .began)
        XCTAssertEqual(outputs.first!.progress, 0.75 * (1 - exp(-(1.0 / 120) / 0.08)), accuracy: 0.000001)
        let first = outputs.last!.progress
        swipe.move(by: -0.5, at: 0.01)
        outputs = swipe.frame(at: 0.02)
        XCTAssertGreaterThan(outputs.last!.progress, first)
        for tick in 3...100 { outputs += swipe.frame(at: Double(tick) / 120) }
        XCTAssertEqual(outputs.last?.phase, .ended)
        XCTAssertEqual(outputs.last!.progress, 0.25, accuracy: 0.000001)
        XCTAssertEqual(outputs.last!.velocity, 0)
        XCTAssertFalse(swipe.isActive)
        XCTAssertTrue(swipe.frame(at: 2).isEmpty)
    }

    func testDirectionReversesBeforeReleaseAndNewInputExtendsIdle() {
        var swipe = SwipeState()
        swipe.move(by: 0.75, at: 0)
        let before = swipe.frame(at: 0.02).last!.progress
        swipe.move(by: -1, at: 0.03)
        XCTAssertLessThan(swipe.frame(at: 0.04).last!.progress, before)
        for tick in 5...17 { _ = swipe.frame(at: Double(tick) / 120) }
        swipe.move(by: 0.001, at: 0.15)
        for tick in 18...77 { _ = swipe.frame(at: Double(tick) / 120) }
        XCTAssertTrue(swipe.isActive)
        let stillFollowing = swipe.frame(at: 0.66)
        XCTAssertFalse(stillFollowing.contains { $0.phase == .ended })
        XCTAssertTrue(swipe.isActive)
        let ended = swipe.frame(at: 0.72)
        XCTAssertEqual(ended.last?.phase, .ended)
        XCTAssertEqual(ended.last!.progress, -0.249, accuracy: 0.000001)
    }

    func testChainingNeverPostsBeyondOneSpaceAndCarriesRemainder() {
        for direction in [-1.0, 1.0] {
            var swipe = SwipeState()
            swipe.move(by: 2.25 * direction, at: 0)
            var outputs: [SwipeOutput] = []
            for tick in 1...180 { outputs += swipe.frame(at: Double(tick) / 120) }
            XCTAssertTrue(outputs.allSatisfy { abs($0.progress) <= 1 })
            let ends = outputs.filter { $0.phase == .ended }
            XCTAssertEqual(ends.count, 3)
            XCTAssertEqual(ends.map(\.progress), [direction, direction, 0.25 * direction])
            XCTAssertFalse(swipe.isActive)
        }
    }

    func testCancellationAndIdleDeadline() {
        var swipe = SwipeState()
        swipe.move(by: 0.05, at: 0)
        _ = swipe.frame(at: 0.01)
        XCTAssertEqual(swipe.cancel().first?.phase, .cancelled)
        XCTAssertTrue(swipe.cancel().isEmpty)
        XCTAssertTrue(swipe.frame(at: 1).isEmpty)
        swipe.move(by: 0.001, at: 2)
        for tick in 1...58 { _ = swipe.frame(at: 2 + Double(tick) / 120) }
        XCTAssertFalse(swipe.frame(at: 2.49).contains { $0.phase == .ended })
        XCTAssertTrue(swipe.frame(at: 2.51).contains { $0.phase == .ended })
    }

    func testExactIntegerEndRetainsRetriesAcrossEmptyIdleFrame() {
        for distance in [-2.0, -1.0, 1.0, 2.0] {
            var swipe = SwipeState()
            var retry = SwipeEndRetryState()
            swipe.move(by: distance, at: 0)
            var timerReplacements = 0
            var sawBoundaryWhileActive = false
            for tick in 1...180 {
                let outputs = swipe.frame(at: Double(tick) / 120)
                for output in outputs {
                    if retry.observe(output) { timerReplacements += 1 }
                    if output.phase == .ended {
                        sawBoundaryWhileActive = sawBoundaryWhileActive || swipe.isActive
                        XCTAssertEqual(retry.pending, output)
                    }
                }
            }
            XCTAssertTrue(sawBoundaryWhileActive)
            XCTAssertFalse(swipe.isActive)
            XCTAssertEqual(retry.pending?.phase, .ended)
            XCTAssertEqual(retry.pending?.progress, distance > 0 ? 1 : -1)
            XCTAssertGreaterThan(Double(timerReplacements), 0)
        }
    }

    func testNextChainBeginAndPauseCancelStaleEndRetries() {
        var swipe = SwipeState()
        var retry = SwipeEndRetryState()
        swipe.move(by: 1.25, at: 0)
        var sawEnd = false
        var sawNextBegin = false
        for tick in 1...180 {
            for output in swipe.frame(at: Double(tick) / 120) {
                let changed = retry.observe(output)
                if output.phase == .ended && !sawEnd {
                    sawEnd = true
                    XCTAssertTrue(changed)
                    XCTAssertEqual(retry.pending?.progress, 1)
                } else if output.phase == .began && sawEnd {
                    sawNextBegin = true
                    XCTAssertTrue(changed)
                    XCTAssertNil(retry.pending)
                }
            }
        }
        XCTAssertTrue(sawNextBegin)
        XCTAssertEqual(retry.pending?.progress, 0.25)
        retry.cancel()
        XCTAssertNil(retry.pending)
        XCTAssertFalse(retry.observe(.init(phase: .changed, progress: 0.1)))
        XCTAssertNil(retry.pending)
    }

    func testIdleDisconnectCancelsRetriesAndRequiresExplicitReactivation() {
        var capture = MouseCaptureState()
        capture.enable(targetConnected: true)
        var swipe = SwipeState()
        swipe.move(by: 0.75, at: 0)
        for tick in 1...180 {
            for output in swipe.frame(at: Double(tick) / 120) { _ = capture.endRetry.observe(output) }
        }
        XCTAssertFalse(swipe.isActive)
        XCTAssertTrue(capture.isEnabled)
        XCTAssertEqual(capture.endRetry.pending?.phase, .ended)
        XCTAssertTrue(capture.vertical.move(pixels: 100, speed: 0.25, at: 0))
        XCTAssertTrue(capture.observeTarget(connected: false))
        XCTAssertFalse(capture.isEnabled)
        XCTAssertNil(capture.endRetry.pending)
        XCTAssertFalse(capture.vertical.isActive)
        XCTAssertEqual(capture.vertical.residualPixels, 0)
        XCTAssertFalse(capture.observeTarget(connected: true))
        XCTAssertFalse(capture.isEnabled)
        capture.enable(targetConnected: true)
        XCTAssertTrue(capture.isEnabled)

        // Explicit activation may wait for the first connection, but its loss pauses.
        capture.pause()
        capture.enable(targetConnected: false)
        XCTAssertFalse(capture.observeTarget(connected: false))
        XCTAssertTrue(capture.isEnabled)
        XCTAssertFalse(capture.observeTarget(connected: true))
        XCTAssertTrue(capture.isEnabled)
        XCTAssertTrue(capture.observeTarget(connected: false))
        XCTAssertFalse(capture.isEnabled)
    }

    func testVerticalSmoothingIsSlowerAndPreservesScaledDisplacement() {
        var scroll = VerticalScrollState()
        XCTAssertTrue(scroll.move(pixels: 400, speed: 0.25, at: 0))
        let first = scroll.frame(at: 1.0 / 120)
        XCTAssertGreaterThan(Double(first), 0)
        XCTAssertLessThan(Double(first), 100)
        var total = Int(first)
        for tick in 2...240 { total += Int(scroll.frame(at: Double(tick) / 120)) }
        XCTAssertEqual(total, 100)
        XCTAssertEqual(scroll.residualPixels, 0, accuracy: 0.000001)
        XCTAssertFalse(scroll.isActive)
        XCTAssertEqual(scroll.frame(at: 3), 0)

        XCTAssertTrue(scroll.move(pixels: -103, speed: 0.25, at: 4))
        total = 0
        for tick in 1...240 { total += Int(scroll.frame(at: 4 + Double(tick) / 120)) }
        XCTAssertEqual(Double(total) + scroll.residualPixels, -25.75, accuracy: 0.000001)
    }

    func testVerticalSubpixelsSpeedChangesAndCancellation() {
        var scroll = VerticalScrollState()
        var total = 0
        for input in 0..<10 {
            let start = Double(input)
            XCTAssertTrue(scroll.move(pixels: 1, speed: 0.1, at: start))
            for tick in 1...100 { total += Int(scroll.frame(at: start + Double(tick) / 120)) }
        }
        XCTAssertEqual(total, 1)
        XCTAssertEqual(scroll.residualPixels, 0, accuracy: 0.000001)
        XCTAssertTrue(scroll.move(pixels: 100, speed: 0.25, at: 11))
        total = Int(scroll.frame(at: 11.01))
        XCTAssertTrue(scroll.move(pixels: 100, speed: 0.5, at: 11.02))
        for tick in 2...240 { total += Int(scroll.frame(at: 11 + Double(tick) / 120)) }
        XCTAssertEqual(total, 75)
        XCTAssertTrue(scroll.move(pixels: 100, speed: 0.25, at: 14))
        scroll.cancel()
        XCTAssertFalse(scroll.isActive)
        XCTAssertEqual(scroll.residualPixels, 0)
        XCTAssertEqual(scroll.frame(at: 15), 0)
        XCTAssertFalse(scroll.move(pixels: .nan, speed: 0.25, at: 15))
        XCTAssertEqual(VerticalScrollState.clampSpeed(.nan), 0.1)
        XCTAssertEqual(VerticalScrollState.clampSpeed(0), 0.1)
        XCTAssertEqual(VerticalScrollState.clampSpeed(5), 1)
    }

    func testAccelerationAndSmoothness() {
        // Off: identical to the plain scale, however fast the wheel spins.
        var plain = VerticalScrollState()
        for i in 0..<10 { XCTAssertTrue(plain.move(pixels: 40, speed: 1, acceleration: 0, at: Double(i) * 0.01)) }
        XCTAssertEqual(plain.residualPixels, 400, accuracy: 0.000001)
        // On: a fast spin travels farther, a lone notch does not.
        var fast = VerticalScrollState()
        for i in 0..<10 { XCTAssertTrue(fast.move(pixels: 40, speed: 1, acceleration: 1, at: Double(i) * 0.01)) }
        XCTAssertGreaterThan(fast.residualPixels, 800)
        XCTAssertLessThan(fast.residualPixels, 1600.001)
        var slow = VerticalScrollState()
        XCTAssertTrue(slow.move(pixels: 10, speed: 1, acceleration: 1, at: 0))
        XCTAssertLessThan(slow.residualPixels, 10.8)
        // Gain fades once the wheel pauses.
        XCTAssertTrue(slow.move(pixels: 10, speed: 1, acceleration: 1, at: 5))
        XCTAssertLessThan(slow.residualPixels, 21.6)
        // Smoothness: less glide emits more in the first frame.
        var quick = VerticalScrollState(), glide = VerticalScrollState()
        XCTAssertTrue(quick.move(pixels: 400, speed: 1, at: 0))
        XCTAssertTrue(glide.move(pixels: 400, speed: 1, at: 0))
        XCTAssertGreaterThan(Double(quick.frame(at: 0.01, smoothness: 0)), Double(glide.frame(at: 0.01, smoothness: 1)))
        XCTAssertEqual(VerticalScrollState.clampUnit(.nan, default: 0.5), 0.5)
        XCTAssertEqual(VerticalScrollState.clampUnit(3, default: 0), 1)
    }

    func testShortcutDisplayAndPlaybackFlags() {
        let right = KeyShortcut.make(keyCode: 124, flags: [.maskControl, .maskSecondaryFn, .maskNumericPad])
        XCTAssertEqual(right.display, "⌃→")
        XCTAssertEqual(right.modifiers, CGEventFlags.maskControl.rawValue)
        XCTAssertTrue(right.playbackFlags.contains(.maskSecondaryFn))
        XCTAssertTrue(right.playbackFlags.contains(.maskNumericPad))
        XCTAssertTrue(right.playbackFlags.contains(.maskControl))
        let letter = KeyShortcut.make(keyCode: 0, flags: [.maskCommand, .maskShift])
        XCTAssertEqual(letter.display, "⇧⌘A")
        XCTAssertFalse(letter.playbackFlags.contains(.maskSecondaryFn))
        XCTAssertEqual(KeyShortcut.make(keyCode: 200, flags: [], character: "ç").display, "Ç")
        XCTAssertEqual(KeyShortcut.make(keyCode: 200, flags: []).display, "?")
    }

    func testVerticalFilteringPreservesOtherInput() {
        let wheel = WheelInput(horizontal: 0, vertical: -20)
        XCTAssertEqual(wheel.verticalPixels(capable: true), -20)
        XCTAssertNil(wheel.verticalPixels(capable: false))
        var other = wheel
        other = wheel; other.horizontal = 1; XCTAssertNil(other.verticalPixels(capable: true))
        other = wheel; other.rawHorizontal = 1; XCTAssertNil(other.verticalPixels(capable: true))
        other = wheel; other.phase = 1; XCTAssertNil(other.verticalPixels(capable: true))
        other = wheel; other.momentum = 1; XCTAssertNil(other.verticalPixels(capable: true))
        other = wheel; other.synthetic = true; XCTAssertNil(other.verticalPixels(capable: true))
        other = wheel; other.vertical = .infinity; XCTAssertNil(other.verticalPixels(capable: true))
    }

    func testVerticalEventPreservesNaturalScrollMetadataAndContext() {
        for inverted: Int64 in [1, 0] {
            let original = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1,
                                   wheel1: -12, wheel2: 0, wheel3: 0)!
            original.flags = [.maskShift]
            original.location = CGPoint(x: 200, y: 300)
            original.setIntegerValueField(VerticalScrollMetadata.inversionField, value: inverted)
            let metadata = VerticalScrollMetadata(event: original)
            let before = CGEvent(source: nil)!.location
            let output = metadata.makeEvent(pixels: -3)!
            let after = CGEvent(source: nil)!.location
            XCTAssertEqual(output.getIntegerValueField(VerticalScrollMetadata.inversionField), inverted)
            XCTAssertEqual(NSEvent(cgEvent: output)!.isDirectionInvertedFromDevice, inverted != 0)
            XCTAssertEqual(output.flags, original.flags)
            // Never the stale input position: posting it would warp the pointer back.
            // The live cursor may move during the check, so accept anything between both readings.
            XCTAssertTrue((min(before.x, after.x) - 2...max(before.x, after.x) + 2).contains(output.location.x))
            XCTAssertTrue((min(before.y, after.y) - 2...max(before.y, after.y) + 2).contains(output.location.y))
            XCTAssertEqual(output.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), -3)
            XCTAssertEqual(output.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 0)
            XCTAssertEqual(output.getIntegerValueField(.scrollWheelEventIsContinuous), 1)
            XCTAssertEqual(output.getIntegerValueField(.eventSourceUserData), 0x4d455341)
            var changed = metadata
            changed.invertedFromDevice = inverted == 0 ? 1 : 0
            XCTAssertFalse(metadata.isCompatible(with: changed))
            changed = metadata
            changed.flags = [.maskCommand]
            XCTAssertFalse(metadata.isCompatible(with: changed))
        }
    }

    func testActiveFilterNeedsAccessibilityRatherThanListenPermission() {
        var permission = MousePermissionState(accessibility: true, inputMonitoring: false, eventPosting: true)
        XCTAssertTrue(permission.canAttemptCapture)
        permission.eventPosting = false
        XCTAssertTrue(permission.canAttemptCapture)
        permission.accessibility = false
        permission.inputMonitoring = true
        XCTAssertFalse(permission.canAttemptCapture)
        XCTAssertTrue(permission.pausedStatus.contains("Accessibility"))
        XCTAssertFalse(permission.pausedStatus.contains("Input Monitoring"))
    }

    func testPausedPermissionStatusUpdatesWithoutActivatingCapture() {
        var capture = MouseCaptureState()
        var permission = MousePermissionState(accessibility: false, inputMonitoring: false, eventPosting: false)
        XCTAssertEqual(capture.updatePermissions(permission), permission.pausedStatus)
        XCTAssertFalse(capture.isEnabled)
        permission.accessibility = true
        XCTAssertTrue(capture.updatePermissions(permission)!.contains("granted"))
        XCTAssertFalse(capture.isEnabled)
        XCTAssertNil(capture.updatePermissions(permission))
        XCTAssertTrue(permission.tapFailureStatus.contains("capture"))
        permission.accessibility = false
        XCTAssertEqual(capture.updatePermissions(permission), permission.pausedStatus)
        XCTAssertFalse(capture.isEnabled)
    }

    func testFilteringAndCapabilityFailurePassThrough() {
        let wheel = WheelInput(horizontal: 2, vertical: 0)
        XCTAssertEqual(wheel.steps(capable: true), 2)
        XCTAssertNil(wheel.steps(capable: false))
        var changed = wheel
        changed = wheel; changed.vertical = 1; XCTAssertNil(changed.steps(capable: true))
        changed = wheel; changed.phase = 1; XCTAssertNil(changed.steps(capable: true))
        changed = wheel; changed.momentum = 1; XCTAssertNil(changed.steps(capable: true))
        changed = wheel; changed.synthetic = true; XCTAssertNil(changed.steps(capable: true))
        changed = wheel; changed.horizontal = .nan; XCTAssertNil(changed.steps(capable: true))
        changed = wheel; changed.horizontal = 0; XCTAssertNil(changed.steps(capable: true))
        changed = wheel; changed.rawHorizontal = -1; XCTAssertEqual(changed.steps(capable: true), 1)
    }

    func testSettingsClampAndNonfiniteInputDoesNothing() {
        XCTAssertEqual(SwipeState.clampSteps(.nan), 12)
        XCTAssertEqual(SwipeState.clampSteps(.infinity), 12)
        XCTAssertEqual(SwipeState.clampSteps(-1), 2)
        XCTAssertEqual(SwipeState.clampSteps(60), 60)
        XCTAssertEqual(SwipeState.clampSteps(500), 500)
        XCTAssertEqual(SwipeState.clampSteps(999), 500)
        var swipe = SwipeState()
        swipe.move(by: .nan, at: 0)
        XCTAssertFalse(swipe.isActive)
    }

    func testClickReplaysWhenOnlyDragIsMapped() {
        var machine = ButtonGestureMachine(handled: [.drag])
        XCTAssertFalse(machine.down(at: 0).pass)
        let up = machine.up(at: 0.1)
        XCTAssertFalse(up.pass)
        XCTAssertEqual(up.outputs, [.replayClick])
        XCTAssertTrue(machine.isIdle)
    }

    func testDragStartsAfterThresholdAndEnds() {
        var machine = ButtonGestureMachine(handled: [.drag])
        _ = machine.down(at: 0)
        XCTAssertEqual(machine.move(dx: 3, dy: 0).outputs, [])
        XCTAssertEqual(machine.move(dx: 4, dy: 0).outputs, [.dragBegan, .drag(dx: 7, dy: 0)])
        XCTAssertEqual(machine.move(dx: -2, dy: 1).outputs, [.drag(dx: -2, dy: 1)])
        XCTAssertEqual(machine.tick(at: 1).count, 0)
        XCTAssertEqual(machine.up(at: 1.2).outputs, [.dragEnded])
        XCTAssertTrue(machine.isIdle)
    }

    func testUnmappedDragAndHoldFallBackToNativeButton() {
        var dragging = ButtonGestureMachine(handled: [.click])
        _ = dragging.down(at: 0)
        let moved = dragging.move(dx: 10, dy: 0)
        XCTAssertTrue(moved.pass)
        XCTAssertEqual(moved.outputs, [.replayDown])
        XCTAssertTrue(dragging.up(at: 0.2).pass)
        XCTAssertTrue(dragging.isIdle)

        var holding = ButtonGestureMachine(handled: [.click])
        _ = holding.down(at: 0)
        XCTAssertEqual(holding.deadline ?? 0, ButtonGestureMachine.holdDelay, accuracy: 0.0001)
        XCTAssertEqual(holding.tick(at: 0.5), [.replayDown])
        XCTAssertTrue(holding.up(at: 0.8).pass)
    }

    func testHoldFiresOnceAndSwallowsRelease() {
        var machine = ButtonGestureMachine(handled: [.hold])
        _ = machine.down(at: 0)
        XCTAssertEqual(machine.tick(at: 0.2), [])
        XCTAssertEqual(machine.tick(at: 0.46), [.perform(.hold)])
        XCTAssertEqual(machine.tick(at: 0.9), [])
        let up = machine.up(at: 1)
        XCTAssertFalse(up.pass)
        XCTAssertEqual(up.outputs, [])
    }

    func testDoubleClickWaitsForWindowThenFallsBackToClick() {
        var machine = ButtonGestureMachine(handled: [.click, .doubleClick])
        _ = machine.down(at: 0)
        XCTAssertEqual(machine.up(at: 0.05).outputs, [])
        XCTAssertFalse(machine.down(at: 0.2).pass)
        XCTAssertEqual(machine.up(at: 0.25).outputs, [.perform(.doubleClick)])
        XCTAssertTrue(machine.isIdle)

        _ = machine.down(at: 1)
        _ = machine.up(at: 1.05)
        XCTAssertEqual(machine.tick(at: 1.2), [])
        XCTAssertEqual(machine.tick(at: 1.36), [.perform(.click)])
        XCTAssertTrue(machine.isIdle)

        var nativeClick = ButtonGestureMachine(handled: [.doubleClick])
        _ = nativeClick.down(at: 0)
        _ = nativeClick.up(at: 0.05)
        XCTAssertEqual(nativeClick.tick(at: 0.4), [.replayClick])
    }

    func testCancelEndsDragAndProfileResolvesButtons() {
        var machine = ButtonGestureMachine(handled: [.drag])
        _ = machine.down(at: 0)
        _ = machine.move(dx: 20, dy: 0)
        XCTAssertEqual(machine.cancel(), [.dragEnded])
        XCTAssertEqual(machine.cancel(), [])

        var profile = MappingProfile.defaults
        XCTAssertEqual(profile.slot(forButton: 3), .back)
        XCTAssertEqual(profile.slot(forButton: 4), .front)
        XCTAssertNil(profile.slot(forButton: 7))
        profile.topButtonNumber = 7
        XCTAssertEqual(profile.slot(forButton: 7), .top)
        XCTAssertEqual(profile.mapping(.front).action(.drag), .switchSpaces)
        XCTAssertEqual(profile.mapping(.front).action(.click), .standard)
        XCTAssertEqual(profile.mapping(.front).handled, [.drag])
        XCTAssertTrue(profile.mapping(.middle).handled.isEmpty)
        let decoded = try! JSONDecoder().decode(MappingProfile.self, from: try! JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)

        // A middle button that sends ⌘Space (key code 49) replaces the wheel click for that slot.
        let space = KeyButton.number(keyCode: 49)
        XCTAssertEqual(KeyButton.keyCode(space), 49)
        XCTAssertNil(KeyButton.keyCode(4))
        profile.learn(space, for: .middle)
        XCTAssertEqual(profile.slot(forButton: space), .middle)
        XCTAssertNil(profile.slot(forButton: 2))
        XCTAssertEqual(profile.slot(forButton: 7), .top)
        profile.learn(8, for: .top)
        XCTAssertEqual(profile.topButtonNumber, 8)
        // Profiles saved before learned buttons existed still decode.
        let old = try! JSONDecoder().decode(MappingProfile.self, from: Data(#"{"buttons":{}}"#.utf8))
        XCTAssertEqual(old.buttonNumber(.middle), 2)
        XCTAssertEqual(NaturalScroll.multiplier(deviceNatural: true, systemNatural: true), 1)
        XCTAssertEqual(NaturalScroll.multiplier(deviceNatural: false, systemNatural: true), -1)
    }

    func testHorizontalSmoothingUsesSecondAxisAndPauseCancels() {
        var capture = MouseCaptureState()
        capture.enable(targetConnected: true)
        XCTAssertTrue(capture.horizontal.move(pixels: 40, speed: 0.5, at: 0))
        XCTAssertTrue(capture.horizontal.isActive)
        XCTAssertFalse(capture.vertical.isActive)
        capture.pause()
        XCTAssertFalse(capture.horizontal.isActive)
        let source = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0)!
        let event = VerticalScrollMetadata(event: source).makeEvent(pixels: 0, horizontal: 7)!
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2), 7)
        XCTAssertEqual(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), 0)
    }

    func testOneRollSwitchesExactlyOneDesktop() {
        for direction in [-1.0, 1.0] {
            var swipe = SwipeState()
            var outputs: [SwipeOutput] = []
            // A roll of many quick notches still produces a single full switch.
            for notch in 0..<12 {
                let time = Double(notch) * 0.04
                swipe.flick(direction * 3, at: time)
                for tick in 1...4 { outputs += swipe.frame(at: time + Double(tick) / 120) }
            }
            XCTAssertEqual(outputs.filter { $0.phase == .began }.count, 1)
            let ends = outputs.filter { $0.phase == .ended }
            XCTAssertEqual(ends.count, 1)
            XCTAssertEqual(ends.first!.progress, direction)
            XCTAssertFalse(swipe.isActive)
            XCTAssertTrue(outputs.allSatisfy { abs($0.progress) <= 1 })
        }
    }

    func testFlickCompletesQuicklyAndNextRollNeedsPause() {
        var swipe = SwipeState()
        swipe.flick(1, at: 0)
        var outputs: [SwipeOutput] = []
        var time = 0.0
        while swipe.isActive && time < 1 {
            time += 1.0 / 120
            outputs += swipe.frame(at: time)
        }
        XCTAssertLessThan(time, 0.3)
        XCTAssertEqual(outputs.last?.phase, .ended)
        // Still the same roll: less than flickGap since the last notch.
        swipe.flick(1, at: 0.27)
        XCTAssertFalse(swipe.isActive)
        swipe.flick(-1, at: 0.6)
        XCTAssertTrue(swipe.isActive)
        XCTAssertEqual(swipe.cancel().first?.phase, nil)
    }

    func testHorizontalScrollKeyMatchesOnlyChosenModifier() {
        XCTAssertTrue(HorizontalScrollKey.option.isHeld([.maskAlternate]))
        XCTAssertTrue(HorizontalScrollKey.option.isHeld([.maskAlternate, .maskShift]))
        XCTAssertFalse(HorizontalScrollKey.option.isHeld([.maskShift]))
        XCTAssertTrue(HorizontalScrollKey.command.isHeld([.maskCommand]))
        XCTAssertFalse(HorizontalScrollKey.none.isHeld([.maskAlternate, .maskShift, .maskControl, .maskCommand]))
        XCTAssertFalse(HorizontalScrollKey.control.isHeld([]))
        var flags: CGEventFlags = [.maskAlternate, .maskShift]
        flags.remove(HorizontalScrollKey.option.flag)
        XCTAssertEqual(flags, [.maskShift])
    }

    func testHoldingTracksPressUntilReleaseIsSeen() {
        var machine = ButtonGestureMachine(handled: [.click])
        XCTAssertFalse(machine.isHolding)
        _ = machine.down(at: 0)
        XCTAssertTrue(machine.isHolding)
        // Recovering a lost release (physical button already up) still performs the click.
        XCTAssertEqual(machine.up(at: 0.05).outputs, [.perform(.click)])
        XCTAssertFalse(machine.isHolding)
        XCTAssertTrue(machine.isIdle)
    }

    func testRecoveringLostReleaseFinishesPendingGesture() {
        var dragOnly = ButtonGestureMachine(handled: [.drag])
        _ = dragOnly.down(at: 0)
        XCTAssertTrue(dragOnly.isHolding)
        XCTAssertEqual(dragOnly.up(at: 0.1).outputs, [.replayClick])
        var dragging = ButtonGestureMachine(handled: [.drag])
        _ = dragging.down(at: 0)
        _ = dragging.move(dx: 30, dy: 0)
        XCTAssertTrue(dragging.isHolding)
        XCTAssertEqual(dragging.up(at: 0.5).outputs, [.dragEnded])
        XCTAssertFalse(dragging.isHolding)
    }
}

#if !canImport(XCTest) || MESA_MOUSE_SELF_CHECK
@main
struct MouseSelfCheck {
    static func main() {
        let checks = MouseKitTests()
        checks.testFiveHundredStepSwipeStillFollowsGradually()
        checks.testSlowNotchesStayInOneGestureUntilHalfSecondIdle()
        checks.testEasingReversalAndIdleRelease()
        checks.testDirectionReversesBeforeReleaseAndNewInputExtendsIdle()
        checks.testChainingNeverPostsBeyondOneSpaceAndCarriesRemainder()
        checks.testCancellationAndIdleDeadline()
        checks.testExactIntegerEndRetainsRetriesAcrossEmptyIdleFrame()
        checks.testNextChainBeginAndPauseCancelStaleEndRetries()
        checks.testIdleDisconnectCancelsRetriesAndRequiresExplicitReactivation()
        checks.testVerticalSmoothingIsSlowerAndPreservesScaledDisplacement()
        checks.testVerticalSubpixelsSpeedChangesAndCancellation()
        checks.testAccelerationAndSmoothness()
        checks.testShortcutDisplayAndPlaybackFlags()
        checks.testVerticalFilteringPreservesOtherInput()
        checks.testVerticalEventPreservesNaturalScrollMetadataAndContext()
        checks.testActiveFilterNeedsAccessibilityRatherThanListenPermission()
        checks.testPausedPermissionStatusUpdatesWithoutActivatingCapture()
        checks.testFilteringAndCapabilityFailurePassThrough()
        checks.testSettingsClampAndNonfiniteInputDoesNothing()
        checks.testClickReplaysWhenOnlyDragIsMapped()
        checks.testDragStartsAfterThresholdAndEnds()
        checks.testUnmappedDragAndHoldFallBackToNativeButton()
        checks.testHoldFiresOnceAndSwallowsRelease()
        checks.testDoubleClickWaitsForWindowThenFallsBackToClick()
        checks.testCancelEndsDragAndProfileResolvesButtons()
        checks.testHorizontalSmoothingUsesSecondAxisAndPauseCancels()
        checks.testOneRollSwitchesExactlyOneDesktop()
        checks.testFlickCompletesQuicklyAndNextRollNeedsPause()
        checks.testHorizontalScrollKeyMatchesOnlyChosenModifier()
        checks.testHoldingTracksPressUntilReleaseIsSeen()
        checks.testRecoveringLostReleaseFinishesPendingGesture()
        print("PASS: 31 mouse behavior groups")
    }
}
#endif
