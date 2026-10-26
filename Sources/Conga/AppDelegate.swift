import AppKit
import CongaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private let monitor = MultitouchMonitor()
    private let overlay = WorkspaceOverlayWindow()
    private let inputTap = InputTap()
    private let shell = ShellCommandRunner(environment: ShellCommandRunner.loginShellEnvironment())
    /// True from the first frame the overlay shows until the indicator is next hidden.
    private var isPeeking = false
    /// Bumped on every refresh so the results of an older one are dropped.
    private var refreshGeneration = 0
    private var previews: [Int: CGImage] = [:]
    /// The focused workspace as AeroSpace last reported it through `subscribe`, or nil while
    /// no subscription is running.
    private var liveFocus: String?
    /// The monitor each workspace was on at the last refresh, by name.
    private var monitors: [String: Int] = [:]
    private var focusSubscription: RunningCommand?
    /// How long to wait before subscribing again after a subscription ends.
    private var resubscribeDelay = AppDelegate.minimumResubscribeDelay
    private static let minimumResubscribeDelay: Duration = .seconds(5)
    private static let maximumResubscribeDelay: Duration = .seconds(300)
    /// The progress `--preview-workspaces` asked to hold the overlay at.
    private var previewProgress: Double?
    /// Where the left button went down, while it is down.
    private var clickLocation: CGPoint?
    private var model: SettingsModel!
    private var dispatcher: GestureDispatcher!
    private var settingsWindow: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = store.load()
        dispatcher = GestureDispatcher(settings: settings, runner: LoggingRunner(shell: shell))
        dispatcher.onIndicatorUpdate = { [weak self] in self?.apply($0) }
        dispatcher.carryWindow = { [weak self] in self?.windowToCarry() }
        // Asked for here, once, rather than in the middle of a gesture. Without it the
        // overlay shows window names instead of previews.
        CGRequestScreenCaptureAccess()
        // Without it the fingers seeking along the overlay also scroll the window under it,
        // and no window can be carried.
        inputTap.start { [weak self] in self?.clicked($0) }
        inputTap.watchesClicks = settings.isEnabled

        model = SettingsModel(settings: settings)
        model.onChange = { [weak self] settings in
            guard let self else { return }
            store.save(settings)
            dispatcher.settings = settings
            inputTap.watchesClicks = settings.isEnabled
            enabledItem.state = settings.isEnabled ? .on : .off
        }
        settingsWindow = SettingsWindowController(model: model)

        let foundTrackpad = monitor.start { [dispatcher] device, frame in
            dispatcher?.handle(frame, device: device)
        }
        installStatusItem(foundTrackpad: foundTrackpad)
        installEditMenu()
        previewWorkspacesIfRequested()
        subscribeToFocus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        focusSubscription?.terminate()
    }

    private func apply(_ update: IndicatorUpdate) {
        switch update {
        case .showWorkspaces(let progress, let selected, let carrying):
            if !isPeeking {
                isPeeking = true
                inputTap.isBlocking = true
                if liveFocus == nil {
                    // The list may say the wrong workspace is focused. Outline nothing until the
                    // refresh says which one is.
                    dispatcher.workspaces = []
                }
                refreshWorkspaces()
            }
            overlay.show(progress: progress, selected: selected, carrying: carrying)
        case .hide:
            isPeeking = false
            inputTap.isBlocking = false
            overlay.hide()
        }
    }

    private func clicked(_ click: InputTap.Click) {
        if logsTouches {
            print(String(format: "%.3f %@", ProcessInfo.processInfo.systemUptime, String(describing: click)))
            fflush(stdout)
        }
        switch click {
        case .down(let location):
            clickLocation = location
            dispatcher.clickBegan()
        case .up(let location, let moved):
            clickLocation = nil
            if moved, let now = CGEvent(source: nil)?.location, hypot(now.x - location.x, now.y - location.y) > 1 {
                // The mouse-up went elsewhere, and the pointer may have followed it.
                CGWarpMouseCursorPosition(location)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
            dispatcher.clickEnded()
        }
    }

    /// The window under the held click, if it is an ordinary window of another app and the
    /// click has not become a drag. The click is neutralised: from here on it does nothing to
    /// the window.
    private func windowToCarry() -> Int? {
        guard let clickLocation, let (window, bounds) = Self.window(at: clickLocation) else {
            NSLog("Conga: no window under the click to carry")
            return nil
        }
        guard inputTap.neutraliseClick(dropPoint: Self.dropPoint(outside: bounds)) else {
            NSLog("Conga: the click is already a drag; not carrying window %d", window)
            return nil
        }
        NSLog("Conga: carrying window %d", window)
        return window
    }

    /// The window server's ID and bounds for the frontmost window at `point`, in the window
    /// server's top-left coordinates, if it is an ordinary window and not this app's.
    private static func window(at point: CGPoint) -> (Int, CGRect)? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        let ownPID = Int(getpid())
        for info in list {
            guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary), bounds.contains(point),
                  info[kCGWindowAlpha as String] as? Double != 0,
                  info[kCGWindowOwnerPID as String] as? Int != ownPID
            else { continue }
            // A menu, a panel or the like is over the window: nothing to carry.
            guard info[kCGWindowLayer as String] as? Int == 0, let id = info[kCGWindowNumber as String] as? Int else { return nil }
            return (id, bounds)
        }
        return nil
    }

    /// Somewhere outside `window` to deliver a neutralised mouse-up: the top-left corner of its
    /// screen, under the menu bar, or if the window covers that too, far off every screen.
    private static func dropPoint(outside window: CGRect) -> CGPoint {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screen = NSScreen.screens.first { screen in
            let frame = screen.frame
            let flipped = CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
            return flipped.contains(CGPoint(x: window.midX, y: window.midY))
        }
        if let frame = screen?.frame {
            let corner = CGPoint(x: frame.minX + 1, y: primaryTop - frame.maxY + 1)
            if !window.contains(corner) { return corner }
        }
        return CGPoint(x: -100_000, y: -100_000)
    }

    /// Asks AeroSpace what is where and shows that with the previews already in hand, then
    /// captures new previews. The overlay keeps the last result, so the next gesture has
    /// something to show at once.
    private func refreshWorkspaces() {
        refreshGeneration += 1
        let generation = refreshGeneration
        Task {
            async let windows = shell.output(of: WorkspaceOverview.listWindowsCommand)
            async let focused = shell.output(of: WorkspaceOverview.focusedWorkspaceCommand)
            async let monitorsJSON = shell.output(of: WorkspaceOverview.monitorsCommand)
            guard let windowsJSON = await windows else { return }
            let monitors = WorkspaceOverview.monitors(inJSON: await monitorsJSON ?? Data())
            var workspaces = WorkspaceOverview.parse(
                windowsJSON: windowsJSON,
                focusedWorkspace: String(decoding: await focused ?? Data(), as: UTF8.self),
                monitors: monitors
            )
            guard generation == refreshGeneration else { return }
            self.monitors = monitors
            if let liveFocus {
                // Newer than the answer to the query if the focus changed while it ran.
                workspaces = WorkspaceOverview.refocus(workspaces, on: liveFocus, monitors: monitors)
            }
            dispatcher.workspaces = workspaces
            overlay.update(workspaces: workspaces, previews: previews)
            if let previewProgress {
                // No gesture is under way to select anything, so outline what one would start with.
                overlay.show(progress: previewProgress, selected: workspaces.first(where: \.isFocused)?.name)
            }

            let ids = workspaces.flatMap(\.windows).map(\.id)
            let captured = await WindowPreviews.capture(windowIDs: ids, maxPixelSize: 400)
            guard generation == refreshGeneration else { return }
            previews = captured
            overlay.update(workspaces: workspaces, previews: captured)
        }
    }

    /// Follows AeroSpace's focused workspace, so that the next gesture starts on the right
    /// one instead of where the last swipe left it. If AeroSpace is too old to subscribe, or is
    /// not running, tries again later, less and less often.
    private func subscribeToFocus() {
        focusSubscription = shell.lines(of: WorkspaceOverview.subscribeToFocusCommand) { [weak self] line in
            guard let focused = WorkspaceOverview.focusedWorkspace(inEvent: line) else { return }
            Task { @MainActor in self?.focusChanged(to: focused) }
        } completion: { [weak self] _ in
            Task { @MainActor in self?.subscriptionEnded() }
        }
    }

    private func focusChanged(to focused: String) {
        liveFocus = focused
        resubscribeDelay = Self.minimumResubscribeDelay
        let workspaces = WorkspaceOverview.refocus(dispatcher.workspaces, on: focused, monitors: monitors)
        guard workspaces != dispatcher.workspaces else { return }
        dispatcher.workspaces = workspaces
        overlay.update(workspaces: workspaces, previews: previews)
    }

    private func subscriptionEnded() {
        liveFocus = nil
        focusSubscription = nil
        let delay = resubscribeDelay
        resubscribeDelay = min(delay * 2, Self.maximumResubscribeDelay)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.subscribeToFocus()
        }
    }

    /// An accessory app never shows its main menu, but the menu is still where ⌘X, ⌘C, ⌘V and
    /// the rest are looked up. Without it the settings window's text fields ignore them.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem()
        editItem.submenu = edit
        let mainMenu = NSMenu()
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    /// `--preview-workspaces 1` holds the workspace overlay at that progress, for checking its
    /// appearance without a hand on the trackpad.
    private func previewWorkspacesIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--preview-workspaces"),
              arguments.indices.contains(flag + 1),
              let progress = Double(arguments[flag + 1])
        else { return }
        previewProgress = progress
        apply(.showWorkspaces(progress: progress, selected: nil))
    }

    private func installStatusItem(foundTrackpad: Bool) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "figure.stand.line.dotted.figure.stand", accessibilityDescription: "Conga")

        let menu = NSMenu()
        if !foundTrackpad {
            menu.addItem(withTitle: "No trackpad found", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
        }
        enabledItem = menu.addItem(withTitle: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.state = model.settings.isEnabled ? .on : .off
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Conga", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate) {
            item.target = self
        }
        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        model.settings.isEnabled.toggle()
    }

    @objc private func showSettings() {
        settingsWindow.show()
    }
}

/// Runs commands in the login shell's environment and logs the ones that fail, since there is
/// nowhere else for their errors to go.
private struct LoggingRunner: CommandRunning {
    let shell: ShellCommandRunner

    func run(_ command: String) {
        shell.run(command) { status in
            if status != 0 {
                NSLog("Conga: `%@` exited with status %d", command, status)
            }
        }
    }
}
