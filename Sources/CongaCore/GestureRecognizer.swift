public enum SwipeDirection: Equatable, Sendable {
    case left
    case right

    public var opposite: SwipeDirection {
        self == .left ? .right : .left
    }
}

public enum GestureEvent: Equatable, Sendable {
    /// Four fingers are down. `fraction` is 0 until the lower bound is passed and 1 once
    /// releasing would fire.
    case progress(SwipeDirection, fraction: Double)
    /// Fingers were released past the trigger threshold.
    case fired(SwipeDirection)
    /// The gesture ended without firing.
    case cancelled
}

public struct GestureThresholds: Equatable, Sendable {
    /// Horizontal travel, as a fraction of trackpad width, at which progress starts.
    public var lowerBound: Double
    /// Horizontal travel at which releasing fires the command.
    public var trigger: Double

    public init(lowerBound: Double, trigger: Double) {
        self.lowerBound = lowerBound
        self.trigger = trigger
    }
}

/// Turns a stream of touch frames from one trackpad into swipe events.
///
/// The fire decision is made from the displacement at the moment of release, not the peak
/// displacement, so swiping out and back before lifting cancels.
///
/// A gesture has one direction, fixed when the swipe first passes the lower bound. Swiping
/// back past the starting point only undoes it; going the other way takes a new touch. The
/// starting point follows the fingers when they do, so swiping in the original direction
/// again starts from wherever they turned around.
public struct GestureRecognizer: Sendable {
    public static let fingerCount = 4

    private enum State {
        case idle
        /// `travel` is the distance moved in `direction` from the start.
        case tracking(startX: Double, startY: Double, direction: SwipeDirection?, travel: Double)
        /// The gesture is over; wait for every finger to lift before starting another.
        case ended
    }

    private var state = State.idle

    public init() {}

    public mutating func handle(_ frame: TouchFrame, thresholds: GestureThresholds) -> GestureEvent? {
        let count = frame.touches.count

        switch state {
        case .idle:
            if count == Self.fingerCount {
                let (x, y) = centroid(of: frame.touches)
                state = .tracking(startX: x, startY: y, direction: nil, travel: 0)
            } else if count > Self.fingerCount {
                state = .ended
            }
            return nil

        case .tracking(let startX, let startY, let lockedDirection, let lastTravel):
            if count < Self.fingerCount {
                state = count == 0 ? .idle : .ended
                if let lockedDirection, lastTravel >= thresholds.trigger {
                    return .fired(lockedDirection)
                }
                return .cancelled
            }
            if count > Self.fingerCount {
                state = .ended
                return .cancelled
            }

            let (x, y) = centroid(of: frame.touches)
            let dx = x - startX
            let dy = y - startY
            // A mostly vertical swipe belongs to someone else (Mission Control, App Exposé).
            if abs(dy) >= thresholds.lowerBound && abs(dy) > abs(dx) {
                state = .ended
                return .cancelled
            }

            let direction: SwipeDirection = lockedDirection ?? (dx < 0 ? .left : .right)
            let travel = direction == .left ? -dx : dx
            if travel < 0 {
                // Behind the start in a fixed direction: restart from here.
                state = .tracking(startX: x, startY: y, direction: direction, travel: 0)
                return .progress(direction, fraction: 0)
            }
            let isLocked = lockedDirection != nil || travel >= thresholds.lowerBound
            state = .tracking(startX: startX, startY: startY, direction: isLocked ? direction : nil, travel: travel)

            let span = thresholds.trigger - thresholds.lowerBound
            let past = travel - thresholds.lowerBound
            let fraction = span > 0 ? min(max(past / span, 0), 1) : (past >= 0 ? 1 : 0)
            return .progress(direction, fraction: fraction)

        case .ended:
            if count == 0 {
                state = .idle
            }
            return nil
        }
    }

    private func centroid(of touches: [Touch]) -> (x: Double, y: Double) {
        let n = Double(touches.count)
        return (touches.reduce(0) { $0 + $1.x } / n, touches.reduce(0) { $0 + $1.y } / n)
    }
}
