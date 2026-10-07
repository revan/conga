/// Where the on-screen indicator should be for a given gesture progress.
public struct IndicatorLayout: Equatable, Sendable {
    /// Opacity of the whole box, 0...1.
    public var opacity: Double
    /// Horizontal offset of the arrow from the centre of the box, in the same unit as `travel`.
    public var arrowOffset: Double
    /// True once releasing would fire the command.
    public var isArmed: Bool
}

public enum IndicatorModel {
    /// The arrow enters from the edge the fingers came from and reaches the centre at full
    /// progress: a right swipe starts `travel` to the left of centre, a left swipe to the right.
    public static func layout(direction: SwipeDirection, progress: Double, travel: Double) -> IndicatorLayout {
        let progress = min(max(progress, 0), 1)
        let remaining = (1 - progress) * travel
        return IndicatorLayout(
            opacity: progress,
            arrowOffset: direction == .right ? -remaining : remaining,
            isArmed: progress >= 1
        )
    }
}
