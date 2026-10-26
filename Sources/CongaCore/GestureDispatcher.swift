public enum IndicatorUpdate: Equatable, Sendable {
    /// Show the workspace overlay, with the workspace named `selected` outlined. `carrying` is
    /// the ID of the window being carried to another workspace, if any.
    case showWorkspaces(progress: Double, selected: String?, carrying: Int? = nil)
    case hide
}

/// Feeds touch frames through a recognizer per trackpad and reports what the workspace overlay
/// should display. The overlay selects the focused workspace to begin with, then its neighbours
/// as the fingers move sideways, in the direction `Settings.naturalScroll` says. Releasing
/// switches to the selection.
///
/// A swipe made while a click is held on a window carries that window instead. The touch that
/// clicked is left out, so four more fingers make the swipe. Lifting them leaves the overlay
/// open, and four fingers put down again seek on from the selection. Releasing the click moves
/// the window to the selected workspace; releasing it while the fingers are still down leaves
/// the window where it is.
public final class GestureDispatcher {
    public var settings: Settings {
        didSet {
            if oldValue.isEnabled && !settings.isEnabled {
                recognizers.removeAll()
                seekers.removeAll()
                carry = nil
                onIndicatorUpdate?(.hide)
            }
        }
    }

    /// The workspaces the overlay chooses between, in the order they are displayed. Whoever
    /// shows them keeps this up to date.
    public var workspaces: [Workspace] = []

    public var onIndicatorUpdate: ((IndicatorUpdate) -> Void)?

    /// Asked once per held click, when four more fingers come down: the ID of the window to
    /// carry, or nil to treat the swipe as an ordinary one. Whoever answers neutralises the click.
    public var carryWindow: (() -> Int?)?

    private enum Click {
        /// The button is down; nobody has asked about carrying yet.
        case held
        /// Four fingers came down while it was held, and this window, if any, is carried.
        case decided(window: Int?)
    }

    private struct Carry {
        var device: Int
        var window: Int
        /// The four fingers have lifted; the overlay waits for them or the click.
        var fingersLifted = false
    }

    private let runner: any CommandRunning
    private var recognizers: [Int: GestureRecognizer] = [:]
    private var seekers: [Int: WorkspaceSeeker] = [:]
    /// Each trackpad's latest frame, as it came.
    private var lastFrames: [Int: TouchFrame] = [:]
    /// The touches that were down on each trackpad when the click began, left out of its frames
    /// until they lift.
    private var anchors: [Int: Set<Int>] = [:]
    private var click: Click?
    private var carry: Carry?

    public init(settings: Settings, runner: any CommandRunning) {
        self.settings = settings
        self.runner = runner
    }

    public func handle(_ frame: TouchFrame, device: Int = 0) {
        guard settings.isEnabled else { return }
        lastFrames[device] = frame
        var frame = frame
        if let held = anchors[device] {
            let down = held.intersection(frame.touches.map(\.id))
            anchors[device] = down.isEmpty ? nil : down
            frame.touches.removeAll { down.contains($0.id) }
        }
        if case .held = click, frame.touches.filter({ !$0.isPalm }).count >= GestureRecognizer.fingerCount {
            click = .decided(window: carryWindow?())
        }

        let event = recognizers[device, default: GestureRecognizer()].handle(frame, thresholds: settings.thresholds)
        switch event {
        case .peek(let fraction, let offset):
            if carry == nil, case .decided(let window?) = click {
                carry = Carry(device: device, window: window)
            }
            if carry?.device == device { carry?.fingersLifted = false }
            let seeker = WorkspaceSeeker(acceleration: settings.workspaceAcceleration)
            let selected = seekers[device, default: seeker].select(
                offset: settings.naturalScroll ? -offset : offset, timestamp: frame.timestamp, in: workspaces
            )
            let carrying = carry?.device == device ? carry?.window : nil
            onIndicatorUpdate?(.showWorkspaces(progress: fraction, selected: selected?.name, carrying: carrying))
        case .peekReleased:
            if carry?.device == device {
                // The overlay stays up until the click is released.
                carry?.fingersLifted = true
                seekers[device]?.resume()
                recognizers[device]?.startsSeeking = true
                return
            }
            onIndicatorUpdate?(.hide)
            // The selection as last shown, from the workspaces as they are now.
            if let selected = seekers[device]?.selection(in: workspaces), !selected.isFocused {
                runner.run(WorkspaceOverview.switchCommand(to: selected.name))
            }
            seekers[device] = nil
        case .cancelled:
            if carry?.device == device { carry = nil }
            seekers[device] = nil
            onIndicatorUpdate?(.hide)
        case nil:
            break
        }
    }

    /// The left button went down. The touches down at the time are the clicking finger.
    public func clickBegan() {
        guard settings.isEnabled else { return }
        click = .held
        for (device, frame) in lastFrames {
            let down = Set(frame.touches.filter { !$0.isPalm }.map(\.id))
            anchors[device] = down.isEmpty ? nil : down
        }
    }

    /// The left button went up. A carried window whose fingers have lifted moves to the
    /// selected workspace, unless it is already there.
    public func clickEnded() {
        click = nil
        guard let carry else { return }
        self.carry = nil
        recognizers[carry.device]?.startsSeeking = false
        if carry.fingersLifted {
            if let selected = seekers[carry.device]?.selection(in: workspaces),
               !selected.windows.contains(where: { $0.id == carry.window })
            {
                runner.run(WorkspaceOverview.moveWindowCommand(carry.window, to: selected.name))
            }
        } else {
            recognizers[carry.device]?.end()
        }
        seekers[carry.device] = nil
        onIndicatorUpdate?(.hide)
    }
}
