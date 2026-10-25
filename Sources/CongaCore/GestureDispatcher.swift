public enum IndicatorUpdate: Equatable, Sendable {
    /// Show the workspace overlay, with the workspace named `selected` outlined.
    case showWorkspaces(progress: Double, selected: String?)
    case hide
}

/// Feeds touch frames through a recognizer per trackpad and reports what the workspace overlay
/// should display. The overlay selects the focused workspace to begin with, then its neighbours
/// as the fingers move sideways, in the direction `Settings.naturalScroll` says. Releasing
/// switches to the selection.
public final class GestureDispatcher {
    public var settings: Settings {
        didSet {
            if oldValue.isEnabled && !settings.isEnabled {
                recognizers.removeAll()
                seekers.removeAll()
                onIndicatorUpdate?(.hide)
            }
        }
    }

    /// The workspaces the overlay chooses between, in the order they are displayed. Whoever
    /// shows them keeps this up to date.
    public var workspaces: [Workspace] = []

    public var onIndicatorUpdate: ((IndicatorUpdate) -> Void)?

    private let runner: any CommandRunning
    private var recognizers: [Int: GestureRecognizer] = [:]
    private var seekers: [Int: WorkspaceSeeker] = [:]

    public init(settings: Settings, runner: any CommandRunning) {
        self.settings = settings
        self.runner = runner
    }

    public func handle(_ frame: TouchFrame, device: Int = 0) {
        guard settings.isEnabled else { return }

        let event = recognizers[device, default: GestureRecognizer()].handle(frame, thresholds: settings.thresholds)
        switch event {
        case .peek(let fraction, let offset):
            let seeker = WorkspaceSeeker(acceleration: settings.workspaceAcceleration)
            let selected = seekers[device, default: seeker].select(
                offset: settings.naturalScroll ? -offset : offset, timestamp: frame.timestamp, in: workspaces
            )
            onIndicatorUpdate?(.showWorkspaces(progress: fraction, selected: selected?.name))
        case .peekReleased:
            onIndicatorUpdate?(.hide)
            // The selection as last shown, from the workspaces as they are now.
            if let selected = seekers[device]?.selection(in: workspaces), !selected.isFocused {
                runner.run(WorkspaceOverview.switchCommand(to: selected.name))
            }
            seekers[device] = nil
        case .cancelled:
            seekers[device] = nil
            onIndicatorUpdate?(.hide)
        case nil:
            break
        }
    }
}
