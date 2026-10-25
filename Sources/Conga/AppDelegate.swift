import AppKit
import CongaCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private let monitor = MultitouchMonitor()
    private let overlay = WorkspaceOverlayWindow()
    private let scrollBlocker = ScrollBlocker()
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
    private var model: SettingsModel!
    private var dispatcher: GestureDispatcher!
    private var settingsWindow: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = store.load()
        dispatcher = GestureDispatcher(settings: settings, runner: LoggingRunner(shell: shell))
        dispatcher.onIndicatorUpdate = { [weak self] in self?.apply($0) }
        // Asked for here, once, rather than in the middle of a gesture. Without it the
        // overlay shows window names instead of previews.
        CGRequestScreenCaptureAccess()
        // Without it the fingers seeking along the overlay also scroll the window under it.
        scrollBlocker.start()

        model = SettingsModel(settings: settings)
        model.onChange = { [weak self] settings in
            guard let self else { return }
            store.save(settings)
            dispatcher.settings = settings
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
        case .showWorkspaces(let progress, let selected):
            if !isPeeking {
                isPeeking = true
                scrollBlocker.isBlocking = true
                if liveFocus == nil {
                    // The list may say the wrong workspace is focused. Outline nothing until the
                    // refresh says which one is.
                    dispatcher.workspaces = []
                }
                refreshWorkspaces()
            }
            overlay.show(progress: progress, selected: selected)
        case .hide:
            isPeeking = false
            scrollBlocker.isBlocking = false
            overlay.hide()
        }
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
