import Foundation

public struct Settings: Equatable, Sendable {
    public static let triggerRange = 0.05...0.80
    public static let minimumIndicatorStart = 0.01
    /// The indicator must start at least this far below the trigger.
    public static let minimumSpan = 0.01
    public static let accelerationRange = 0.0...5.0

    public var isEnabled = true
    /// When set, the fingers push the content: moving them left moves the workspace overlay's
    /// selection right, and the reverse.
    public var naturalScroll = false
    /// Fraction of trackpad width (or height, for a swipe up) at which the workspace overlay
    /// is fully shown. A sideways swipe seeks from there.
    public var triggerFraction = 0.20
    /// Fraction of trackpad width (or height) at which the workspace overlay starts to fade in.
    public var indicatorStartFraction = 0.05
    /// How much faster sideways movement moves the workspace overlay's selection further.
    /// 0 is one workspace per `WorkspaceSeeker.step` at any speed.
    public var workspaceAcceleration = 1.5

    public init() {}

    public var thresholds: GestureThresholds {
        GestureThresholds(lowerBound: indicatorStartFraction, trigger: triggerFraction)
    }

    /// A copy with the thresholds forced into range and the indicator start below the trigger.
    public func normalized() -> Settings {
        var copy = self
        copy.triggerFraction = min(max(triggerFraction, Self.triggerRange.lowerBound), Self.triggerRange.upperBound)
        copy.indicatorStartFraction = min(
            max(indicatorStartFraction, Self.minimumIndicatorStart),
            copy.triggerFraction - Self.minimumSpan
        )
        copy.workspaceAcceleration = min(
            max(workspaceAcceleration, Self.accelerationRange.lowerBound),
            Self.accelerationRange.upperBound
        )
        return copy
    }
}

public final class SettingsStore {
    private enum Key {
        static let isEnabled = "isEnabled"
        static let naturalScroll = "naturalScroll"
        static let triggerFraction = "triggerFraction"
        static let indicatorStartFraction = "indicatorStartFraction"
        static let workspaceAcceleration = "workspaceAcceleration"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Settings {
        var settings = Settings()
        if let value = defaults.object(forKey: Key.isEnabled) as? Bool { settings.isEnabled = value }
        if let value = defaults.object(forKey: Key.naturalScroll) as? Bool { settings.naturalScroll = value }
        if let value = defaults.object(forKey: Key.triggerFraction) as? Double { settings.triggerFraction = value }
        if let value = defaults.object(forKey: Key.indicatorStartFraction) as? Double {
            settings.indicatorStartFraction = value
        }
        if let value = defaults.object(forKey: Key.workspaceAcceleration) as? Double {
            settings.workspaceAcceleration = value
        }
        return settings.normalized()
    }

    public func save(_ settings: Settings) {
        let settings = settings.normalized()
        defaults.set(settings.isEnabled, forKey: Key.isEnabled)
        defaults.set(settings.naturalScroll, forKey: Key.naturalScroll)
        defaults.set(settings.triggerFraction, forKey: Key.triggerFraction)
        defaults.set(settings.indicatorStartFraction, forKey: Key.indicatorStartFraction)
        defaults.set(settings.workspaceAcceleration, forKey: Key.workspaceAcceleration)
    }
}
