import CoreGraphics

/// Decides what to do with a held left click whose window is being carried to another
/// workspace, so that the app under the click neither follows the seeking fingers nor sees a
/// completed click.
///
/// A click is only neutralised before it has become a drag: once the pointer has moved more
/// than `dragSlop` with the button down, the click belongs to the app (a file drag, a text
/// selection, a resize) and is left alone. A neutralised click's drags are dropped, and its
/// mouse-up is delivered somewhere outside the window, so that buttons and links cancel their
/// press as they do when the pointer is dragged off them before release.
public struct ClickFilter: Sendable {
    /// How far, in points, the pointer may move with the button down before the click is a drag.
    public static let dragSlop = 4.0

    /// Where the button went down, while it is down.
    private var start: CGPoint?
    private var hasDragged = false
    public private(set) var isNeutralising = false

    public init() {}

    public mutating func mouseDown(at point: CGPoint) {
        start = point
        hasDragged = false
        isNeutralising = false
    }

    /// Returns true if the drag event should be dropped.
    public mutating func mouseDragged(to point: CGPoint) -> Bool {
        if isNeutralising { return true }
        if let start, hypot(point.x - start.x, point.y - start.y) > Self.dragSlop {
            hasDragged = true
        }
        return false
    }

    /// Returns true if the mouse-up should be moved away from the clicked window.
    public mutating func mouseUp() -> Bool {
        defer {
            start = nil
            isNeutralising = false
        }
        return isNeutralising
    }

    /// Neutralises the click being held, unless it has already become a drag or the button is
    /// up. Returns whether it did.
    public mutating func neutralise() -> Bool {
        guard start != nil, !hasDragged else { return false }
        isNeutralising = true
        return true
    }
}
