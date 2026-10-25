import Testing

@testable import CongaCore

/// A frame with `count` fingers spread around the centroid (`x`, `y`).
func frame(_ count: Int, x: Double = 0.5, y: Double = 0.5) -> TouchFrame {
    let touches = (0..<count).map { i in
        let spread = (Double(i) - Double(count - 1) / 2) * 0.1
        return Touch(id: i, x: x + spread, y: y)
    }
    return TouchFrame(touches: touches)
}

/// `frame` with one more touch, far from the fingers, as a palm makes.
func withPalm(_ frame: TouchFrame, x: Double = 0.9, y: Double = 0.1) -> TouchFrame {
    TouchFrame(timestamp: frame.timestamp, touches: frame.touches + [Touch(id: 99, x: x, y: y)])
}

/// `frame` with a touch the framework labels as a palm.
func withLabelledPalm(_ frame: TouchFrame, x: Double = 0.05, y: Double = 0.7) -> TouchFrame {
    TouchFrame(timestamp: frame.timestamp, touches: frame.touches + [Touch(id: 98, x: x, y: y, part: 6)])
}

private let thresholds = GestureThresholds(lowerBound: 0.05, trigger: 0.20)

/// Feeds frames through a fresh recognizer and returns the non-nil events.
private func events(_ frames: [TouchFrame], thresholds: GestureThresholds = thresholds) -> [GestureEvent] {
    var recognizer = GestureRecognizer()
    return frames.compactMap { recognizer.handle($0, thresholds: thresholds) }
}

private func peek(_ event: GestureEvent?) -> Double? {
    if case .peek(let fraction, _) = event { fraction } else { nil }
}

private func offset(_ event: GestureEvent?) -> Double? {
    if case .peek(_, let offset) = event { offset } else { nil }
}

/// True if `event` is a peek at `fraction` and, within rounding, `offset`.
private func isPeek(_ event: GestureEvent, _ fraction: Double, offset expected: Double) -> Bool {
    guard let actual = peek(event), let moved = offset(event) else { return false }
    return abs(actual - fraction) < 1e-9 && abs(moved - expected) < 1e-9
}

@Suite struct GestureRecognizerTests {
    @Test func sidewaysSwipeFadesInBetweenLowerBoundAndTrigger() throws {
        let result = events([frame(4), frame(4, x: 0.625), frame(4, x: 0.70), frame(4, x: 0.95)])
        let fractions = result.compactMap { peek($0) }
        try #require(fractions.count == 3)
        #expect(abs(fractions[0] - 0.5) < 1e-9)
        #expect(abs(fractions[1] - 1) < 1e-9)
        #expect(fractions[2] == 1)
    }

    @Test func sidewaysSwipeBelowLowerBoundShowsNothing() {
        #expect(events([frame(4), frame(4, x: 0.53)]).isEmpty)
    }

    @Test func releasingPastTriggerIsAPeekRelease() {
        let result = events([frame(4), frame(4, x: 0.6), frame(4, x: 0.75), frame(0)])
        #expect(result.count == 3)
        #expect(result.last == .peekReleased)
    }

    @Test func leftSwipePastTriggerIsAPeekRelease() {
        #expect(events([frame(4), frame(4, x: 0.25), frame(0)]).last == .peekReleased)
    }

    @Test func releasingBelowTriggerCancels() {
        let result = events([frame(4), frame(4, x: 0.65), frame(0)])
        #expect(result.last == .cancelled)
        #expect(!result.contains(.peekReleased))
    }

    @Test func sidewaysSeekingIsMeasuredFromTheTrigger() throws {
        let result = events([frame(4), frame(4, x: 0.6), frame(4, x: 0.8), frame(4, x: 0.4), frame(0)])
        try #require(result.count == 4)
        #expect(isPeek(result[0], 1.0 / 3, offset: 0))
        #expect(isPeek(result[1], 1, offset: 0.1))
        // Swiping back once fully shown seeks back rather than fading out.
        #expect(isPeek(result[2], 1, offset: -0.3))
        #expect(result[3] == .peekReleased)
    }

    @Test func leftSwipeSeeksFromTheTrigger() {
        let result = events([frame(4), frame(4, x: 0.2), frame(0)])
        #expect(result.count == 2 && isPeek(result[0], 1, offset: -0.1))
    }

    @Test func reversingBeforeTriggerFadesOutAndCancels() {
        let result = events([frame(4), frame(4, x: 0.65), frame(4, x: 0.6), frame(4, x: 0.52), frame(0)])
        #expect(isPeek(result[0], 2.0 / 3, offset: 0))
        #expect(peek(result[1])! < peek(result[0])!)
        #expect(result[2] == .peek(fraction: 0, offset: 0))
        #expect(result.last == .cancelled)
    }

    @Test func reversingThroughStartDoesNotSwitchDirection() {
        let result = events([frame(4), frame(4, x: 0.6), frame(4, x: 0.2), frame(0)])
        #expect(result.count == 3)
        #expect(result[1] == .peek(fraction: 0, offset: 0))
        #expect(result.last == .cancelled)
    }

    @Test func swipingAgainAfterOvershootStartsFromTurnaroundPoint() throws {
        let result = events([frame(4), frame(4, x: 0.6), frame(4, x: 0.3), frame(4, x: 0.4), frame(4, x: 0.55), frame(0)])
        try #require(result.count == 5)
        #expect(result[1] == .peek(fraction: 0, offset: 0))
        #expect(isPeek(result[2], 1.0 / 3, offset: 0))
        #expect(isPeek(result[3], 1, offset: 0.05))
        #expect(result[4] == .peekReleased)
    }

    @Test func overshootDoesNotCountAsVerticalSwipe() {
        let result = events([
            frame(4), frame(4, x: 0.6, y: 0.57), frame(4, x: 0.4, y: 0.57), frame(4, x: 0.65, y: 0.57), frame(0),
        ])
        #expect(isPeek(result[2], 1, offset: 0.05))
        #expect(result.last == .peekReleased)
    }

    @Test func directionIsNotFixedBeforeLowerBound() {
        let result = events([frame(4), frame(4, x: 0.52), frame(4, x: 0.2), frame(0)])
        #expect(result.count == 2 && isPeek(result[0], 1, offset: -0.1))
        #expect(result.last == .peekReleased)
    }

    @Test func oppositeDirectionWorksAfterLiftingAndTouchingAgain() {
        let result = events([
            frame(4), frame(4, x: 0.6), frame(4, x: 0.2), frame(0), frame(4, x: 0.5), frame(4, x: 0.2), frame(0),
        ])
        #expect(result.filter { $0 == .cancelled }.count == 1)
        #expect(isPeek(result[result.count - 2], 1, offset: -0.1))
        #expect(result.last == .peekReleased)
    }

    @Test(arguments: [1, 2, 3, 5]) func otherFingerCountsNeverTrigger(count: Int) {
        let result = events([frame(count), frame(count, x: 0.9), frame(0)])
        #expect(result.isEmpty)
    }

    @Test func fifthFingerBeforeDirectionIsFixedCancels() {
        let result = events([frame(4), frame(5), frame(4, x: 0.9), frame(0)])
        #expect(result == [.cancelled])
    }

    @Test func extraTouchAfterDirectionIsFixedIsIgnored() {
        let result = events([frame(4), frame(4, x: 0.8), withPalm(frame(4, x: 0.8)), frame(4, x: 0.8), frame(0)])
        #expect(result.count == 4)
        #expect(result.dropLast().allSatisfy { isPeek($0, 1, offset: 0.1) })
        #expect(result.last == .peekReleased)
    }

    @Test func staggeredLiftReleasesOnce() {
        let result = events([
            frame(4), frame(4, x: 0.8), frame(3, x: 0.8), frame(2, x: 0.8), frame(1, x: 0.8), frame(0),
        ])
        #expect(result.filter { $0 == .peekReleased }.count == 1)
        #expect(result.last == .peekReleased)
    }

    @Test func fingerReturningDuringLiftDoesNotStartNewGesture() {
        let result = events([frame(4), frame(4, x: 0.6), frame(3, x: 0.6), frame(4, x: 0.6), frame(4, x: 0.9), frame(0)])
        #expect(result.count == 2 && result.last == .cancelled)
    }

    @Test func newGestureStartsAfterAllFingersLift() {
        let result = events([frame(4), frame(4, x: 0.8), frame(0), frame(4, x: 0.8), frame(4, x: 0.5), frame(0)])
        #expect(result.filter { $0 == .peekReleased }.count == 2)
        #expect(isPeek(result[result.count - 2], 1, offset: -0.1))
    }

    @Test func swipeDownIsIgnored() {
        let result = events([frame(4), frame(4, x: 0.52, y: 0.2), frame(4, x: 0.9, y: 0.2), frame(0)])
        #expect(result == [.cancelled])
    }

    @Test func swipeUpPeeksFromLowerBoundToTrigger() throws {
        let result = events([frame(4), frame(4, y: 0.55), frame(4, y: 0.625), frame(4, y: 0.70), frame(4, y: 0.95)])
        let fractions = result.compactMap { peek($0) }
        try #require(fractions.count == 4)
        #expect(abs(fractions[0]) < 1e-9)
        #expect(abs(fractions[1] - 0.5) < 1e-9)
        #expect(abs(fractions[2] - 1) < 1e-9)
        #expect(fractions[3] == 1)
    }

    @Test func swipeUpBelowLowerBoundDoesNotPeek() {
        let result = events([frame(4), frame(4, y: 0.53)])
        #expect(result.allSatisfy { peek($0) == nil })
    }

    @Test func releasingAfterSwipeUpIsAPeekRelease() {
        let result = events([frame(4), frame(4, y: 0.9), frame(0)])
        #expect(result == [.peek(fraction: 1, offset: 0), .peekReleased])
    }

    @Test func peekReleaseNeedsOnlyTheLowerBound() {
        #expect(events([frame(4), frame(4, y: 0.6), frame(0)]).last == .peekReleased)
    }

    @Test func swipingBackDownBeforeReleaseCancelsPeek() {
        let result = events([frame(4), frame(4, y: 0.9), frame(4, y: 0.53), frame(0)])
        #expect(result.last == .cancelled)
    }

    @Test func sidewaysMovementDuringPeekIsReportedFromWhereItLocked() throws {
        let result = events([frame(4), frame(4, x: 0.52, y: 0.8), frame(4, x: 0.72, y: 0.8), frame(4, x: 0.32, y: 0.9)])
        let offsets = result.compactMap { if case .peek(_, let offset) = $0 { offset } else { nil } }
        try #require(offsets.count == 3)
        #expect(offsets[0] == 0)
        #expect(abs(offsets[1] - 0.2) < 1e-9)
        #expect(abs(offsets[2] + 0.2) < 1e-9)
    }

    @Test func sidewaysOffsetSurvivesSwipingBackDown() throws {
        let result = events([frame(4), frame(4, y: 0.8), frame(4, x: 0.7, y: 0.3)])
        #expect(peek(result.last) == 0)
        guard case .peek(_, let offset) = result.last else { return }
        #expect(abs(offset - 0.2) < 1e-9)
    }

    @Test func swipingBackDownUndoesPeekAndRestartsFromTurnaroundPoint() throws {
        let result = events([frame(4), frame(4, y: 0.8), frame(4, y: 0.6), frame(4, y: 0.3), frame(4, y: 0.4), frame(4, y: 0.5)])
        try #require(result.count == 5)
        #expect(result[0] == .peek(fraction: 1, offset: 0))
        #expect(peek(result[1])! < 1)
        #expect(result[2] == .peek(fraction: 0, offset: 0))
        #expect(abs(peek(result[3])! - 1.0 / 3) < 1e-9)
        #expect(result[4] == .peek(fraction: 1, offset: 0))
    }

    @Test func horizontalDriftAfterSwipeUpStaysAPeek() {
        let result = events([frame(4), frame(4, y: 0.8), frame(4, x: 0.9, y: 0.8), frame(0)])
        #expect(result.allSatisfy { peek($0) == 1 || $0 == .peekReleased })
        #expect(result.last == .peekReleased)
    }

    @Test func seekingAtADownwardAngleDoesNotFadePeek() {
        // Fingers moving left and down at about 30 degrees, as a hand that is not level does.
        var frames = [frame(4), frame(4, y: 0.75)]
        for step in 1...6 {
            frames.append(frame(4, x: 0.5 - 0.05 * Double(step), y: 0.75 - 0.03 * Double(step)))
        }
        let result = events(frames + [frame(0)])
        #expect(result.dropLast().allSatisfy { peek($0) == 1 })
        #expect(result.last == .peekReleased)
    }

    @Test func swipingDownAfterSeekingAtAnAngleStillCancels() {
        let result = events([
            frame(4), frame(4, y: 0.75), frame(4, x: 0.3, y: 0.65), frame(4, x: 0.3, y: 0.3), frame(0),
        ])
        #expect(peek(result[1]) == 1)
        #expect(peek(result[2]) == 0)
        #expect(result.last == .cancelled)
    }

    @Test func verticalDriftAfterSidewaysSwipeIsIgnored() {
        let result = events([frame(4), frame(4, x: 0.6), frame(4, x: 0.75, y: 0.95), frame(4, x: 0.75, y: 0.1), frame(0)])
        #expect(isPeek(result[0], 1.0 / 3, offset: 0))
        #expect(isPeek(result[1], 1, offset: 0.05))
        #expect(isPeek(result[2], 1, offset: 0.05))
        #expect(result.last == .peekReleased)
    }

    @Test func palmDuringPeekDoesNotMoveItOrEndIt() {
        let result = events([
            frame(4), frame(4, y: 0.8), withPalm(frame(4, y: 0.8)), withPalm(frame(4, y: 0.8), x: 0.1, y: 0.9),
            frame(4, y: 0.8), frame(0),
        ])
        #expect(result == Array(repeating: .peek(fraction: 1, offset: 0), count: 4) + [.peekReleased])
    }

    @Test func palmRestingBeforeFingersLandDoesNotStopSwipeUp() {
        let palm = withLabelledPalm(frame(0))
        let result = events([
            palm, withLabelledPalm(frame(4)), withLabelledPalm(frame(4, y: 0.8)), withLabelledPalm(frame(4, y: 0.9)), palm,
            frame(0),
        ])
        #expect(result == [.peek(fraction: 1, offset: 0), .peek(fraction: 1, offset: 0), .peekReleased])
    }

    @Test func labelledPalmLandingBeforeDirectionIsFixedDoesNotCancel() {
        let result = events([frame(4), withLabelledPalm(frame(4)), withLabelledPalm(frame(4, x: 0.8)), frame(0)])
        #expect(result.last == .peekReleased)
    }

    @Test func labelledPalmDoesNotMakeUpTheFourthFinger() {
        let result = events([withLabelledPalm(frame(3)), withLabelledPalm(frame(3, x: 0.9)), frame(0)])
        #expect(result.isEmpty)
    }

    @Test func newGestureCanStartWhileAPalmStaysDown() {
        let result = events([
            withLabelledPalm(frame(4)), withLabelledPalm(frame(4, x: 0.8)), withLabelledPalm(frame(0)),
            withLabelledPalm(frame(4, x: 0.8)), withLabelledPalm(frame(4, x: 0.5)), withLabelledPalm(frame(0)),
        ])
        #expect(result.filter { $0 == .peekReleased }.count == 2)
        #expect(isPeek(result[result.count - 2], 1, offset: -0.1))
    }

    @Test func fingerSlidingOffTheEdgeKeepsPeekHeld() {
        let fingers = frame(4, x: 0.8, y: 0.8)
        let oneLifted = TouchFrame(touches: Array(fingers.touches.dropLast()))
        let movedOn = TouchFrame(touches: oneLifted.touches.map { Touch(id: $0.id, x: $0.x - 0.1, y: $0.y) })
        let result = events([frame(4, x: 0.8), fingers, oneLifted, movedOn, frame(0)])
        // The centroid jumps when the finger lifts; that frame neither seeks nor fades.
        #expect(result.count == 4)
        #expect(result.first == .peek(fraction: 1, offset: 0))
        #expect(result.dropFirst().first == .peek(fraction: 1, offset: 0))
        guard result.count == 4, case .peek(1, let moved) = result[2] else { Issue.record("\(result)"); return }
        #expect(abs(moved + 0.1) < 1e-9)
        #expect(result.last == .peekReleased)
    }

    @Test func liftedFingerReturningDuringPeekIsIgnored() {
        let fingers = frame(4, y: 0.8)
        let oneLifted = TouchFrame(touches: Array(fingers.touches.dropFirst()))
        let result = events([frame(4), fingers, withPalm(fingers), withPalm(oneLifted), fingers, frame(0)])
        let still = result.dropLast().allSatisfy { if case .peek(1, let offset) = $0 { abs(offset) < 1e-9 } else { false } }
        #expect(result.count == 5 && still)
        #expect(result.last == .peekReleased)
    }

    @Test func liftingTwoFingersEndsPeek() {
        let fingers = frame(4, y: 0.8)
        let twoLifted = TouchFrame(touches: Array(fingers.touches.dropFirst(2)))
        let result = events([frame(4), fingers, twoLifted, fingers, frame(0)])
        #expect(result == [.peek(fraction: 1, offset: 0), .peekReleased])
    }

    @Test func liftingOneFingerBeforeTheOverlayIsFullyShownCancels() {
        let result = events([frame(4), frame(4, x: 0.6), frame(3, x: 0.6), frame(0)])
        #expect(result.count == 2 && result.last == .cancelled)
    }

    @Test func fingerSlidingOffTheEdgeKeepsSidewaysSeekingHeld() {
        let fingers = frame(4, x: 0.8)
        let oneLifted = TouchFrame(touches: Array(fingers.touches.dropLast()))
        let movedOn = TouchFrame(touches: oneLifted.touches.map { Touch(id: $0.id, x: $0.x - 0.1, y: $0.y) })
        let result = events([frame(4), fingers, oneLifted, movedOn, frame(0)])
        #expect(result.count == 4)
        #expect(isPeek(result[0], 1, offset: 0.1))
        #expect(isPeek(result[1], 1, offset: 0.1))
        #expect(isPeek(result[2], 1, offset: 0))
        #expect(result.last == .peekReleased)
    }

    @Test func diagonalSwipeThatIsMostlyHorizontalStillShowsTheOverlay() {
        let result = events([frame(4), frame(4, x: 0.8, y: 0.6), frame(0)])
        #expect(result.last == .peekReleased)
    }

    @Test func customThresholdsAreHonoured() {
        let custom = GestureThresholds(lowerBound: 0.10, trigger: 0.50)
        #expect(events([frame(4), frame(4, x: 0.8), frame(0)], thresholds: custom).last == .cancelled)
        #expect(events([frame(4), frame(4, x: 0.58)], thresholds: custom).isEmpty)
        #expect(events([frame(4, x: 0.2), frame(4, x: 0.75), frame(0)], thresholds: custom).last == .peekReleased)
    }
}
