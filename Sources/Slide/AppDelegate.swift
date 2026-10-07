import AppKit
import SlideCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private let monitor = MultitouchMonitor()
    private let indicator = IndicatorWindow()
    private var model: SettingsModel!
    private var dispatcher: GestureDispatcher!
    private var settingsWindow: SettingsWindowController!
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = store.load()
        dispatcher = GestureDispatcher(settings: settings, runner: LoggingRunner())
        dispatcher.onIndicatorUpdate = { [indicator] in indicator.apply($0) }

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
        previewIndicatorIfRequested()
    }

    /// `--preview-indicator 0.6` holds the indicator at that progress, for checking its
    /// appearance without a hand on the trackpad. A negative value previews a left swipe.
    private func previewIndicatorIfRequested() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--preview-indicator"),
              arguments.indices.contains(flag + 1),
              let progress = Double(arguments[flag + 1])
        else { return }
        indicator.apply(.show(progress < 0 ? .left : .right, progress: abs(progress)))
    }

    private func installStatusItem(foundTrackpad: Bool) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: "Slide")

        let menu = NSMenu()
        if !foundTrackpad {
            menu.addItem(withTitle: "No trackpad found", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
        }
        enabledItem = menu.addItem(withTitle: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.state = model.settings.isEnabled ? .on : .off
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Slide", action: #selector(NSApplication.terminate), keyEquivalent: "q")
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
    let shell = ShellCommandRunner(environment: ShellCommandRunner.loginShellEnvironment())

    func run(_ command: String) {
        shell.run(command) { status in
            if status != 0 {
                NSLog("Slide: `%@` exited with status %d", command, status)
            }
        }
    }
}
