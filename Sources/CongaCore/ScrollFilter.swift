/// Decides which scroll events to keep from other apps while the workspace overlay is open, so
/// that seeking along the row does not also scroll the window under the pointer.
///
/// The phases are the values of `CGScrollPhase` and `CGMomentumScrollPhase`. A trackpad scroll
/// goes mayBegin/began, changed…, ended, then momentum begin, continue…, end. A mouse wheel
/// sets neither phase.
public struct ScrollFilter: Sendable {
    public static let phaseBegan = 1
    public static let phaseMayBegin = 128

    /// True while the overlay is open: every scroll and gesture event is dropped.
    public var isBlocking = false {
        didSet {
            if oldValue && !isBlocking { isDraining = true }
        }
    }

    /// After the overlay closes, the rest of the scroll it swallowed, and the momentum that
    /// follows it, is dropped too, until a new scroll starts.
    private var isDraining = false

    public init() {}

    /// False once there is nothing left to drop, so events need not be looked at.
    public var isActive: Bool { isBlocking || isDraining }

    /// Returns true if the scroll event should be dropped.
    public mutating func dropsScroll(phase: Int, momentumPhase: Int) -> Bool {
        if isBlocking { return true }
        guard isDraining else { return false }
        let startsNewScroll = phase == Self.phaseBegan || phase == Self.phaseMayBegin
        let isPhaseless = phase == 0 && momentumPhase == 0
        if startsNewScroll || isPhaseless {
            isDraining = false
            return false
        }
        return true
    }

    /// Returns true if a gesture event (magnify, rotate, swipe, …) should be dropped.
    public func dropsGesture() -> Bool {
        isBlocking
    }
}
