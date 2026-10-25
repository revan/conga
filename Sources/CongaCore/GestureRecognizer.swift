public enum GestureEvent: Equatable, Sendable {
    /// Four fingers are down and the workspace overlay is showing. `fraction` is 0 at the lower
    /// bound and 1 at the trigger distance. `offset` is how far the fingers have moved sideways
    /// since the overlay could seek, as a fraction of trackpad width, positive to the right.
    case peek(fraction: Double, offset: Double)
    /// Fingers were released while the overlay could seek.
    case peekReleased
    /// The gesture ended without choosing a workspace.
    case cancelled
}

public struct GestureThresholds: Equatable, Sendable {
    /// Travel, as a fraction of the trackpad's width (or height, for a swipe up), at which
    /// the overlay starts to fade in.
    public var lowerBound: Double
    /// Travel at which the overlay is fully shown.
    public var trigger: Double

    public init(lowerBound: Double, trigger: Double) {
        self.lowerBound = lowerBound
        self.trigger = trigger
    }
}

/// Turns a stream of touch frames from one trackpad into workspace overlay events.
///
/// A swipe up or sideways fades the overlay in, reported as `.peek`. A gesture has one
/// direction, fixed when the swipe first passes the lower bound. A swipe down belongs to
/// someone else.
///
/// A sideways swipe fades the overlay in between the lower bound and the trigger distance.
/// Swiping back past the starting point only undoes it; going the other way takes a new touch.
/// The starting point follows the fingers when they do, so swiping in the original direction
/// again starts from wherever they turned around. Releasing before the trigger cancels. Once
/// past the trigger the overlay stays fully shown, every sideways movement from there seeks,
/// and releasing is `.peekReleased`.
///
/// A swipe up seeks from the moment it is recognised. It has no trigger distance: releasing
/// anywhere past the lower bound, where the overlay starts to show, is `.peekReleased`, and
/// swiping back down until it has faded out cancels. Frames that move more sideways than
/// vertically do not change how far up it is, so seeking at an angle does not fade it.
///
/// Touches the framework labels as a palm are dropped before anything else, so a palm resting
/// on the trackpad neither counts as a finger nor stops four fingers starting a gesture.
///
/// The gesture follows the four touches that started it, by identifier. Once its direction is
/// fixed, any other touch, such as a palm brushing the trackpad, is ignored rather than moving
/// the centroid or ending the gesture; lifting any of the four ends it. While seeking it stays
/// held with three of the four, since seeking can slide a finger off the trackpad's edge.
/// Before the direction is fixed, a fifth touch cancels, so five fingers put down together are
/// never a swipe.
public struct GestureRecognizer: Sendable {
    public static let fingerCount = 4
    /// How many of the four fingers keep a seeking gesture held after the others lift.
    public static let minimumHeldFingers = 3

    private enum Lock {
        /// Fading the overlay in. `sign` is 1 for fingers moving right, -1 for left.
        case sideways(sign: Double)
        /// The overlay seeks. `originX` is where sideways travel is measured from; `lastX` and
        /// `lastY` are where the fingers were in the previous frame. `isUp` says the gesture
        /// is a swipe up, which fades with vertical travel; a sideways one stays fully shown.
        case seeking(originX: Double, lastX: Double, lastY: Double, isUp: Bool)
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
            if case .seeking(let originX, let lastX, _, let isUp) = lock, touches.count < fingers.count,
                touches.count >= Self.minimumHeldFingers
            {
                // A finger slid off the edge while seeking. Follow the rest, and count this
                // frame as no movement, so the centroid jumping to the remaining fingers
                // neither seeks nor fades.
                let (x, y) = centroid(of: touches)
                state = .tracking(
                    fingers: Set(touches.map(\.id)), startX: startX, startY: startY,
                    lock: .seeking(originX: originX + x - lastX, lastX: x, lastY: y, isUp: isUp), travel: lastTravel
                )
                return .peek(fraction: fraction(of: lastTravel, thresholds: thresholds), offset: lastX - originX)
            }
            if touches.count < fingers.count {
                state = count == 0 ? .idle : .ended
                if case .seeking = lock, fraction(of: lastTravel, thresholds: thresholds) > 0 {
                    return .peekReleased
                }
                return .cancelled
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
                    fingers: fingers, startX: startX, startY: startY,
                    lock: .seeking(originX: x, lastX: x, lastY: y, isUp: true), travel: dy
                )
                return .peek(fraction: fraction(of: dy, thresholds: thresholds), offset: 0)
            }

            if case .seeking(let originX, let lastX, let lastY, let isUp) = lock {
                // Seeking sideways is rarely level, so a frame that moves more sideways than
                // up or down leaves the vertical travel alone. Below zero is back below the
                // start, and restarts from here. A sideways swipe ignores vertical movement.
                let stepX = x - lastX
                let stepY = y - lastY
                let travel = isUp && abs(stepY) > abs(stepX) ? max(lastTravel + stepY, 0) : lastTravel
                state = .tracking(
                    fingers: fingers, startX: startX, startY: startY,
                    lock: .seeking(originX: originX, lastX: x, lastY: y, isUp: isUp), travel: travel
                )
                return .peek(fraction: fraction(of: travel, thresholds: thresholds), offset: x - originX)
            }

            let lockedSign: Double? = if case .sideways(let sign) = lock { sign } else { nil }
            let sign = lockedSign ?? (dx < 0 ? -1 : 1)
            let travel = dx * sign
            if travel < 0 {
                // Behind the start in a fixed direction: restart from here.
                state = .tracking(fingers: fingers, startX: x, startY: y, lock: .sideways(sign: sign), travel: 0)
                return .peek(fraction: 0, offset: 0)
            }
            if travel >= thresholds.trigger {
                // Fully shown. From here on sideways movement seeks, measured from the trigger
                // distance so that a frame jumping past it does not lose the excess.
                let originX = startX + sign * thresholds.trigger
                state = .tracking(
                    fingers: fingers, startX: startX, startY: startY,
                    lock: .seeking(originX: originX, lastX: x, lastY: y, isUp: false), travel: travel
                )
                return .peek(fraction: 1, offset: x - originX)
            }
            guard lockedSign != nil || travel >= thresholds.lowerBound else {
                state = .tracking(fingers: fingers, startX: startX, startY: startY, lock: nil, travel: travel)
                return nil
            }
            state = .tracking(fingers: fingers, startX: startX, startY: startY, lock: .sideways(sign: sign), travel: travel)
            return .peek(fraction: fraction(of: travel, thresholds: thresholds), offset: 0)

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
