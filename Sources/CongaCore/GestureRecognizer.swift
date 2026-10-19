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
    /// trigger distance. `offset` is how far the fingers have since moved sideways, as a
    /// fraction of trackpad width, positive to the right.
    case peek(fraction: Double, offset: Double)
    /// Fingers were released after a swipe up, past the lower bound.
    case peekReleased
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
/// Up is a direction too, reported as `.peek`. It has no trigger distance: releasing anywhere
/// past the lower bound, where the swipe starts to show, is `.peekReleased`. A swipe down
/// belongs to someone else. Once a swipe up is recognised, frames that move more sideways than
/// vertically do not change how far up it is, so seeking along the overlay at an angle does
/// not fade it.
///
/// Touches the framework labels as a palm are dropped before anything else, so a palm resting
/// on the trackpad neither counts as a finger nor stops four fingers starting a gesture.
///
/// The gesture follows the four touches that started it, by identifier. Once its direction is
/// fixed, any other touch, such as a palm brushing the trackpad, is ignored rather than moving
/// the centroid or ending the gesture; lifting any of the four ends it. A swipe up is the
/// exception: seeking can slide a finger off the trackpad's edge, so it stays held while three
/// of the four are down. Before the direction is fixed, a fifth touch cancels, so five fingers
/// put down together are never a swipe.
public struct GestureRecognizer: Sendable {
    public static let fingerCount = 4
    /// How many of the four fingers keep a swipe up held after the others lift.
    public static let minimumHeldFingers = 3

    private enum Lock {
        case horizontal(SwipeDirection)
        /// `originX` is where the fingers were when the swipe up was recognised; `lastX` and
        /// `lastY` are where they were in the previous frame.
        case up(originX: Double, lastX: Double, lastY: Double)
    }

    private enum State {
        case idle
        /// `fingers` are the identifiers of the touches being followed. `travel` is the
        /// distance moved in the locked direction from the start, or for a swipe up, the
        /// vertical distance counted so far.
        case tracking(fingers: Set<Int>, startX: Double, startY: Double, lock: Lock?, travel: Double)
        /// The gesture is over; wait for every finger to lift before starting another.
        case ended
    }

    private var state = State.idle

    public init() {}

    public mutating func handle(_ frame: TouchFrame, thresholds: GestureThresholds) -> GestureEvent? {
        var frame = frame
        frame.touches.removeAll(where: \.isPalm)
        let count = frame.touches.count

        switch state {
        case .idle:
            if count == Self.fingerCount {
                let (x, y) = centroid(of: frame.touches)
                state = .tracking(fingers: Set(frame.touches.map(\.id)), startX: x, startY: y, lock: nil, travel: 0)
            } else if count > Self.fingerCount {
                state = .ended
            }
            return nil

        case .tracking(let fingers, let startX, let startY, let lock, let lastTravel):
            let touches = frame.touches.filter { fingers.contains($0.id) }
            if case .up(let originX, let lastX, let lastY) = lock, touches.count < fingers.count,
                touches.count >= Self.minimumHeldFingers
            {
                // A finger slid off the edge while seeking. Follow the rest, and count this
                // frame as no movement, so the centroid jumping to the remaining fingers
                // neither seeks nor fades.
                let (x, y) = centroid(of: touches)
                state = .tracking(
                    fingers: Set(touches.map(\.id)), startX: startX, startY: startY,
                    lock: .up(originX: originX + x - lastX, lastX: x, lastY: y), travel: lastTravel
                )
                return .peek(fraction: fraction(of: lastTravel, thresholds: thresholds), offset: lastX - originX)
            }
            if touches.count < fingers.count {
                state = count == 0 ? .idle : .ended
                switch lock {
                case .horizontal(let direction) where lastTravel >= thresholds.trigger:
                    return .fired(direction)
                case .up where fraction(of: lastTravel, thresholds: thresholds) > 0:
                    return .peekReleased
                default:
                    return .cancelled
                }
            }
            if lock == nil && count > touches.count {
                state = .ended
                return .cancelled
            }

            let (x, y) = centroid(of: touches)
            let dx = x - startX
            let dy = y - startY
            if case nil = lock, abs(dy) >= thresholds.lowerBound && abs(dy) > abs(dx) {
                // The origin is bottom-left, so up is positive. A mostly downward swipe
                // belongs to someone else (App Exposé).
                guard dy > 0 else {
                    state = .ended
                    return .cancelled
                }
                state = .tracking(
                    fingers: fingers, startX: startX, startY: startY, lock: .up(originX: x, lastX: x, lastY: y), travel: dy
                )
                return .peek(fraction: fraction(of: dy, thresholds: thresholds), offset: 0)
            }

            if case .up(let originX, let lastX, let lastY) = lock {
                // Seeking sideways is rarely level, so a frame that moves more sideways than
                // up or down leaves the vertical travel alone. Below zero is back below the
                // start, and restarts from here.
                let stepX = x - lastX
                let stepY = y - lastY
                let travel = abs(stepY) > abs(stepX) ? max(lastTravel + stepY, 0) : lastTravel
                state = .tracking(
                    fingers: fingers, startX: startX, startY: startY, lock: .up(originX: originX, lastX: x, lastY: y),
                    travel: travel
                )
                return .peek(fraction: fraction(of: travel, thresholds: thresholds), offset: x - originX)
            }

            let lockedDirection: SwipeDirection? = if case .horizontal(let locked) = lock { locked } else { nil }
            let direction = lockedDirection ?? (dx < 0 ? .left : .right)
            let travel = direction == .left ? -dx : dx
            if travel < 0 {
                // Behind the start in a fixed direction: restart from here.
                state = .tracking(fingers: fingers, startX: x, startY: y, lock: .horizontal(direction), travel: 0)
                return .progress(direction, fraction: 0)
            }
            let isLocked = lockedDirection != nil || travel >= thresholds.lowerBound
            state = .tracking(
                fingers: fingers, startX: startX, startY: startY, lock: isLocked ? .horizontal(direction) : nil, travel: travel
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
