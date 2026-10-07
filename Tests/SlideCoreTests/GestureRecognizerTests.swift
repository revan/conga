import Testing

@testable import SlideCore

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

    @Test func verticalSwipeIsIgnored() {
        let result = events([frame(4), frame(4, x: 0.52, y: 0.8), frame(4, x: 0.9, y: 0.8), frame(0)])
        #expect(result == [.cancelled])
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
