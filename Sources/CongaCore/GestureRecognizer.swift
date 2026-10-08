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
    /// Four fingers are down and swiping up. `fraction` is 0 at the lower bound and 1 at the
    /// trigger distance. Nothing fires for a swipe up; lifting ends it with `.cancelled`.
    case peek(fraction: Double)
    /// Fingers were released past the trigger threshold.
    case fired(SwipeDirection)
    /// The gesture ended without firing.
    case cancelled
}

public struct GestureThresholds: Equatable, Sendable {
    /// Travel, as a fraction of the trackpad's width (or height, for a swipe up), at which
    /// progress starts.
    public var lowerBound: Double
    /// Travel at which releasing fires the command.
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
///
/// Up is a direction too, reported as `.peek`. A swipe down belongs to someone else.
public struct GestureRecognizer: Sendable {
    public static let fingerCount = 4

    private enum Lock {
        case horizontal(SwipeDirection)
        case up
    }

    private enum State {
        case idle
        /// `travel` is the distance moved in the locked direction from the start.
        case tracking(startX: Double, startY: Double, lock: Lock?, travel: Double)
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
                state = .tracking(startX: x, startY: y, lock: nil, travel: 0)
            } else if count > Self.fingerCount {
                state = .ended
            }
            return nil

        case .tracking(let startX, let startY, var lock, let lastTravel):
            if count < Self.fingerCount {
                state = count == 0 ? .idle : .ended
                if case .horizontal(let direction) = lock, lastTravel >= thresholds.trigger {
                    return .fired(direction)
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
            if lock == nil && abs(dy) >= thresholds.lowerBound && abs(dy) > abs(dx) {
                // The origin is bottom-left, so up is positive. A mostly downward swipe
                // belongs to someone else (App Exposé).
                guard dy > 0 else {
                    state = .ended
                    return .cancelled
                }
                lock = .up
            }

            if case .up = lock {
                if dy < 0 {
                    // Back below the start: restart from here.
                    state = .tracking(startX: x, startY: y, lock: .up, travel: 0)
                    return .peek(fraction: 0)
                }
                state = .tracking(startX: startX, startY: startY, lock: .up, travel: dy)
                return .peek(fraction: fraction(of: dy, thresholds: thresholds))
            }

            let direction: SwipeDirection
            if case .horizontal(let locked) = lock {
                direction = locked
            } else {
                direction = dx < 0 ? .left : .right
            }
            let travel = direction == .left ? -dx : dx
            if travel < 0 {
                // Behind the start in a fixed direction: restart from here.
                state = .tracking(startX: x, startY: y, lock: .horizontal(direction), travel: 0)
                return .progress(direction, fraction: 0)
            }
            let isLocked = lock != nil || travel >= thresholds.lowerBound
            state = .tracking(
                startX: startX, startY: startY, lock: isLocked ? .horizontal(direction) : nil, travel: travel
            )
            return .progress(direction, fraction: fraction(of: travel, thresholds: thresholds))

        case .ended:
            if count == 0 {
                state = .idle
            }
            return nil
        }
    }

    private func fraction(of travel: Double, thresholds: GestureThresholds) -> Double {
        let span = thresholds.trigger - thresholds.lowerBound
        let past = travel - thresholds.lowerBound
        return span > 0 ? min(max(past / span, 0), 1) : (past >= 0 ? 1 : 0)
    }

    private func centroid(of touches: [Touch]) -> (x: Double, y: Double) {
        let n = Double(touches.count)
        return (touches.reduce(0) { $0 + $1.x } / n, touches.reduce(0) { $0 + $1.y } / n)
    }
}
