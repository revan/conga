import Foundation

public struct Settings: Equatable, Sendable {
    public static let triggerRange = 0.05...0.80
    public static let minimumIndicatorStart = 0.01
    /// The indicator must start at least this far below the trigger.
    public static let minimumSpan = 0.01

    public var isEnabled = true
    /// When set, the fingers push the content: moving them left is a swipe right, and the
    /// reverse. The indicator and the command both follow the swipe, not the fingers.
    public var naturalScroll = true
    public var leftCommand = "aerospace workspace --wrap-around prev"
    public var rightCommand = "aerospace workspace --wrap-around next"
    /// Fraction of trackpad width that must be swiped for release to fire the command.
    public var triggerFraction = 0.20
    /// Fraction of trackpad width at which the indicator starts to appear.
    public var indicatorStartFraction = 0.05

    public init() {}

    public var thresholds: GestureThresholds {
        GestureThresholds(lowerBound: indicatorStartFraction, trigger: triggerFraction)
    }

    /// The swipe that fingers moving in `fingerDirection` perform.
    public func swipeDirection(forFingers fingerDirection: SwipeDirection) -> SwipeDirection {
        naturalScroll ? fingerDirection.opposite : fingerDirection
    }

    public func command(for direction: SwipeDirection) -> String {
        switch direction {
        case .left: leftCommand
        case .right: rightCommand
        }
    }

    /// A copy with the thresholds forced into range and the indicator start below the trigger.
    public func normalized() -> Settings {
        var copy = self
        copy.triggerFraction = min(max(triggerFraction, Self.triggerRange.lowerBound), Self.triggerRange.upperBound)
        copy.indicatorStartFraction = min(
            max(indicatorStartFraction, Self.minimumIndicatorStart),
            copy.triggerFraction - Self.minimumSpan
        )
        return copy
    }
}

public final class SettingsStore {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let naturalScroll = "naturalScroll"
        static let leftCommand = "leftCommand"
        static let rightCommand = "rightCommand"
        static let triggerFraction = "triggerFraction"
        static let indicatorStartFraction = "indicatorStartFraction"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Settings {
        var settings = Settings()
        if let value = defaults.object(forKey: Key.isEnabled) as? Bool { settings.isEnabled = value }
        if let value = defaults.object(forKey: Key.naturalScroll) as? Bool { settings.naturalScroll = value }
        if let value = defaults.string(forKey: Key.leftCommand) { settings.leftCommand = value }
        if let value = defaults.string(forKey: Key.rightCommand) { settings.rightCommand = value }
        if let value = defaults.object(forKey: Key.triggerFraction) as? Double { settings.triggerFraction = value }
        if let value = defaults.object(forKey: Key.indicatorStartFraction) as? Double {
            settings.indicatorStartFraction = value
        }
        return settings.normalized()
    }

    public func save(_ settings: Settings) {
        let settings = settings.normalized()
        defaults.set(settings.isEnabled, forKey: Key.isEnabled)
        defaults.set(settings.naturalScroll, forKey: Key.naturalScroll)
        defaults.set(settings.leftCommand, forKey: Key.leftCommand)
        defaults.set(settings.rightCommand, forKey: Key.rightCommand)
        defaults.set(settings.triggerFraction, forKey: Key.triggerFraction)
        defaults.set(settings.indicatorStartFraction, forKey: Key.indicatorStartFraction)
    }
}
