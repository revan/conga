public enum SwipeDirection: Equatable, Sendable {
    case left
    case right
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
public struct GestureRecognizer: Sendable {
    public static let fingerCount = 4

    private enum State {
        case idle
        case tracking(startX: Double, startY: Double, dx: Double)
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
                state = .tracking(startX: x, startY: y, dx: 0)
            } else if count > Self.fingerCount {
                state = .ended
            }
            return nil

        case .tracking(let startX, let startY, let lastDx):
            if count < Self.fingerCount {
                state = count == 0 ? .idle : .ended
                return abs(lastDx) >= thresholds.trigger ? .fired(direction(of: lastDx)) : .cancelled
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

            state = .tracking(startX: startX, startY: startY, dx: dx)
            let span = thresholds.trigger - thresholds.lowerBound
            let travel = abs(dx) - thresholds.lowerBound
            let fraction = span > 0 ? min(max(travel / span, 0), 1) : (travel >= 0 ? 1 : 0)
            return .progress(direction(of: dx), fraction: fraction)

        case .ended:
            if count == 0 {
                state = .idle
            }
            return nil
        }
    }

    private func direction(of dx: Double) -> SwipeDirection {
        dx < 0 ? .left : .right
    }

    private func centroid(of touches: [Touch]) -> (x: Double, y: Double) {
        let n = Double(touches.count)
        return (touches.reduce(0) { $0 + $1.x } / n, touches.reduce(0) { $0 + $1.y } / n)
    }
}
