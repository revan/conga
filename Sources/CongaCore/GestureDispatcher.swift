public enum IndicatorUpdate: Equatable, Sendable {
    case show(SwipeDirection, progress: Double)
    case hide(fired: Bool)
}

/// Feeds touch frames through a recognizer per trackpad, runs the configured command when a
/// swipe fires, and reports what the indicator should display.
public final class GestureDispatcher {
    public var settings: Settings {
        didSet {
            if oldValue.isEnabled && !settings.isEnabled {
                recognizers.removeAll()
                onIndicatorUpdate?(.hide(fired: false))
            }
        }
    }

    public var onIndicatorUpdate: ((IndicatorUpdate) -> Void)?

    private let runner: any CommandRunning
    private var recognizers: [Int: GestureRecognizer] = [:]

    public init(settings: Settings, runner: any CommandRunning) {
        self.settings = settings
        self.runner = runner
    }

    public func handle(_ frame: TouchFrame, device: Int = 0) {
        guard settings.isEnabled else { return }

        let event = recognizers[device, default: GestureRecognizer()].handle(frame, thresholds: settings.thresholds)
        switch event {
        case .progress(let direction, let fraction):
            onIndicatorUpdate?(.show(direction, progress: fraction))
        case .fired(let direction):
            onIndicatorUpdate?(.hide(fired: true))
            let command = settings.command(for: direction)
            if !command.allSatisfy(\.isWhitespace) {
                runner.run(command)
            }
        case .cancelled:
            onIndicatorUpdate?(.hide(fired: false))
        case nil:
            break
        }
    }
}
