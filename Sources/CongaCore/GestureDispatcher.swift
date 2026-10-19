public enum IndicatorUpdate: Equatable, Sendable {
    case show(SwipeDirection, progress: Double)
    /// A swipe up: show the workspace overlay instead of the arrow, with the workspace
    /// named `selected` outlined.
    case showWorkspaces(progress: Double, selected: String?)
    case hide(fired: Bool)
}

/// Feeds touch frames through a recognizer per trackpad, runs the configured command when a
/// swipe fires, and reports what the indicator should display. The recognizer reports where
/// the fingers went; the swipe that means depends on `Settings.naturalScroll`.
///
/// A swipe up selects a workspace instead: the focused one to begin with, then its neighbours
/// as the fingers move sideways. Releasing switches to the selection.
public final class GestureDispatcher {
    public var settings: Settings {
        didSet {
            if oldValue.isEnabled && !settings.isEnabled {
                recognizers.removeAll()
                seekers.removeAll()
                onIndicatorUpdate?(.hide(fired: false))
            }
        }
    }

    /// The workspaces a swipe up chooses between, in the order they are displayed. Whoever
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
        case .progress(let direction, let fraction):
            onIndicatorUpdate?(.show(settings.swipeDirection(forFingers: direction), progress: fraction))
        case .peek(let fraction, let offset):
            let selected = seekers[device, default: WorkspaceSeeker()].select(offset: offset, in: workspaces)
            onIndicatorUpdate?(.showWorkspaces(progress: fraction, selected: selected?.name))
        case .peekReleased:
            onIndicatorUpdate?(.hide(fired: true))
            // The selection as last shown, from the workspaces as they are now.
            if let selected = seekers[device]?.selection(in: workspaces), !selected.isFocused {
                runner.run(WorkspaceOverview.switchCommand(to: selected.name))
            }
            seekers[device] = nil
        case .fired(let direction):
            onIndicatorUpdate?(.hide(fired: true))
            let command = settings.command(for: settings.swipeDirection(forFingers: direction))
            if !command.allSatisfy(\.isWhitespace) {
                runner.run(command)
            }
        case .cancelled:
            seekers[device] = nil
            onIndicatorUpdate?(.hide(fired: false))
        case nil:
            break
        }
    }
}
