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

private let thresholds = GestureThresholds(lowerBound: 0.05, trigger: 0.20)

/// Feeds frames through a fresh recognizer and returns the non-nil events.
private func events(_ frames: [TouchFrame], thresholds: GestureThresholds = thresholds) -> [GestureEvent] {
    var recognizer = GestureRecognizer()
    return frames.compactMap { recognizer.handle($0, thresholds: thresholds) }
}

private func progress(_ event: GestureEvent?) -> Double? {
    if case .progress(_, let fraction) = event { fraction } else { nil }
}

private func peek(_ event: GestureEvent?) -> Double? {
    if case .peek(let fraction, _) = event { fraction } else { nil }
}

@Suite struct GestureRecognizerTests {
    @Test func firesRightWhenReleasedPastTrigger() {
        let result = events([frame(4), frame(4, x: 0.6), frame(4, x: 0.75), frame(0)])
        #expect(result.last == .fired(.right))
    }

    @Test func firesLeftWhenReleasedPastTrigger() {
        let result = events([frame(4), frame(4, x: 0.25), frame(0)])
        #expect(result.last == .fired(.left))
    }

    @Test func cancelsWhenReleasedBelowTrigger() {
        let result = events([frame(4), frame(4, x: 0.65), frame(0)])
        #expect(result.last == .cancelled)
        #expect(!result.contains(.fired(.right)))
    }

    @Test func progressIsZeroBelowLowerBound() {
        let result = events([frame(4), frame(4, x: 0.53)])
        #expect(result == [.progress(.right, fraction: 0)])
    }

    @Test func progressScalesLinearlyBetweenBounds() throws {
        let result = events([frame(4), frame(4, x: 0.625), frame(4, x: 0.70), frame(4, x: 0.95)])
        let fractions = result.compactMap { progress($0) }
        try #require(fractions.count == 3)
        #expect(abs(fractions[0] - 0.5) < 1e-9)
        #expect(abs(fractions[1] - 1) < 1e-9)
        #expect(fractions[2] == 1)
    }

    @Test func reversingBeforeReleaseCancels() {
        let result = events([frame(4), frame(4, x: 0.8), frame(4, x: 0.6), frame(4, x: 0.52), frame(0)])
        #expect(result.first == .progress(.right, fraction: 1))
        #expect(progress(result[1])! < 1)
        #expect(result[2] == .progress(.right, fraction: 0))
        #expect(result.last == .cancelled)
        #expect(!result.contains(.fired(.right)))
    }

    @Test func reversingThroughStartDoesNotSwitchDirection() {
        let result = events([frame(4), frame(4, x: 0.8), frame(4, x: 0.2), frame(0)])
        #expect(result == [.progress(.right, fraction: 1), .progress(.right, fraction: 0), .cancelled])
    }

    @Test func swipingAgainAfterOvershootStartsFromTurnaroundPoint() throws {
        let result = events([frame(4), frame(4, x: 0.8), frame(4, x: 0.2), frame(4, x: 0.3), frame(4, x: 0.45), frame(0)])
        try #require(result.count == 5)
        #expect(result[1] == .progress(.right, fraction: 0))
        #expect(abs(progress(result[2])! - 1.0 / 3) < 1e-9)
        #expect(result[3] == .progress(.right, fraction: 1))
        #expect(result[4] == .fired(.right))
    }

    @Test func overshootDoesNotCountAsVerticalSwipe() {
        let result = events([
            frame(4), frame(4, x: 0.8, y: 0.57), frame(4, x: 0.4, y: 0.57), frame(4, x: 0.65, y: 0.57), frame(0),
        ])
        #expect(result.last == .fired(.right))
    }

    @Test func directionIsNotFixedBeforeLowerBound() {
        let result = events([frame(4), frame(4, x: 0.52), frame(4, x: 0.2), frame(0)])
        #expect(result == [.progress(.right, fraction: 0), .progress(.left, fraction: 1), .fired(.left)])
    }

    @Test func oppositeDirectionWorksAfterLiftingAndTouchingAgain() {
        let result = events([frame(4), frame(4, x: 0.8), frame(4, x: 0.2), frame(0), frame(4, x: 0.5), frame(4, x: 0.2), frame(0)])
        #expect(result.last == .fired(.left))
        #expect(result.filter { $0 == .cancelled }.count == 1)
    }

    @Test(arguments: [1, 2, 3, 5]) func otherFingerCountsNeverTrigger(count: Int) {
        let result = events([frame(count), frame(count, x: 0.9), frame(0)])
        #expect(result.isEmpty)
    }

    @Test func fifthFingerCancels() {
        let result = events([frame(4), frame(4, x: 0.8), frame(5, x: 0.8), frame(4, x: 0.8), frame(0)])
        #expect(result == [.progress(.right, fraction: 1), .cancelled])
    }

    @Test func staggeredLiftFiresOnce() {
        let result = events([
            frame(4), frame(4, x: 0.8), frame(3, x: 0.8), frame(2, x: 0.8), frame(1, x: 0.8), frame(0),
        ])
        #expect(result == [.progress(.right, fraction: 1), .fired(.right)])
    }

    @Test func fingerReturningDuringLiftDoesNotStartNewGesture() {
        let result = events([frame(4), frame(4, x: 0.8), frame(3, x: 0.8), frame(4, x: 0.8), frame(4, x: 0.2), frame(0)])
        #expect(result == [.progress(.right, fraction: 1), .fired(.right)])
    }

    @Test func newGestureStartsAfterAllFingersLift() {
        let result = events([frame(4), frame(4, x: 0.8), frame(0), frame(4, x: 0.8), frame(4, x: 0.5), frame(0)])
        #expect(result.filter { $0 == .fired(.right) }.count == 1)
        #expect(result.last == .fired(.left))
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

    @Test func verticalDriftAfterHorizontalSwipeDoesNotPeek() {
        let result = events([frame(4), frame(4, x: 0.6), frame(4, x: 0.75, y: 0.95), frame(0)])
        #expect(result.allSatisfy { peek($0) == nil })
        #expect(result.last == .fired(.right))
    }

    @Test func fifthFingerCancelsPeek() {
        let result = events([frame(4), frame(4, y: 0.8), frame(5, y: 0.8), frame(4, y: 0.9), frame(0)])
        #expect(result == [.peek(fraction: 1, offset: 0), .cancelled])
    }

    @Test func diagonalSwipeThatIsMostlyHorizontalStillFires() {
        let result = events([frame(4), frame(4, x: 0.8, y: 0.6), frame(0)])
        #expect(result.last == .fired(.right))
    }

    @Test func customThresholdsAreHonoured() {
        let custom = GestureThresholds(lowerBound: 0.10, trigger: 0.50)
        #expect(events([frame(4), frame(4, x: 0.8), frame(0)], thresholds: custom).last == .cancelled)
        #expect(events([frame(4), frame(4, x: 0.58)], thresholds: custom) == [.progress(.right, fraction: 0)])
        #expect(events([frame(4, x: 0.2), frame(4, x: 0.75), frame(0)], thresholds: custom).last == .fired(.right))
    }
}
