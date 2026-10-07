import Foundation
import Testing

@testable import CongaCore

private final class RecordingRunner: CommandRunning {
    var commands: [String] = []
    func run(_ command: String) { commands.append(command) }
}

@Suite struct GestureDispatcherTests {
    private func makeDispatcher(
        _ settings: Settings = Settings()
    ) -> (GestureDispatcher, RecordingRunner, () -> [IndicatorUpdate]) {
        let runner = RecordingRunner()
        let dispatcher = GestureDispatcher(settings: settings, runner: runner)
        let updates = Updates()
        dispatcher.onIndicatorUpdate = { updates.values.append($0) }
        return (dispatcher, runner, { updates.values })
    }

    private final class Updates {
        var values: [IndicatorUpdate] = []
    }

    @Test func rightSwipeRunsRightCommand() {
        let (dispatcher, runner, updates) = makeDispatcher()
        for f in [frame(4), frame(4, x: 0.8), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands == ["aerospace workspace --wrap-around next"])
        #expect(updates() == [.show(.right, progress: 1), .hide(fired: true)])
    }

    @Test func leftSwipeRunsLeftCommand() {
        let (dispatcher, runner, _) = makeDispatcher()
        for f in [frame(4), frame(4, x: 0.2), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands == ["aerospace workspace --wrap-around prev"])
    }

    @Test func reversedSwipeRunsNothing() {
        let (dispatcher, runner, updates) = makeDispatcher()
        for f in [frame(4), frame(4, x: 0.8), frame(4, x: 0.5), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands.isEmpty)
        #expect(updates() == [.show(.right, progress: 1), .show(.right, progress: 0), .hide(fired: false)])
    }

    @Test func customCommandsAndThresholdsApplyLive() {
        let (dispatcher, runner, _) = makeDispatcher()
        var settings = Settings()
        settings.rightCommand = "echo hi"
        settings.triggerFraction = 0.5
        dispatcher.settings = settings

        for f in [frame(4), frame(4, x: 0.8), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands.isEmpty)
        for f in [frame(4, x: 0.2), frame(4, x: 0.8), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands == ["echo hi"])
    }

    @Test func blankCommandIsNotRun() {
        var settings = Settings()
        settings.rightCommand = "  "
        let (dispatcher, runner, updates) = makeDispatcher(settings)
        for f in [frame(4), frame(4, x: 0.8), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands.isEmpty)
        #expect(updates().last == .hide(fired: true))
    }

    @Test func disabledIgnoresGestures() {
        var settings = Settings()
        settings.isEnabled = false
        let (dispatcher, runner, updates) = makeDispatcher(settings)
        for f in [frame(4), frame(4, x: 0.8), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands.isEmpty)
        #expect(updates().isEmpty)
    }

    @Test func disablingMidGestureHidesIndicatorAndDropsGesture() {
        let (dispatcher, runner, updates) = makeDispatcher()
        dispatcher.handle(frame(4))
        dispatcher.handle(frame(4, x: 0.8))
        dispatcher.settings.isEnabled = false
        dispatcher.handle(frame(0))
        #expect(runner.commands.isEmpty)
        #expect(updates().last == .hide(fired: false))
    }

    @Test func trackpadsAreTrackedIndependently() {
        let (dispatcher, runner, _) = makeDispatcher()
        dispatcher.handle(frame(4), device: 1)
        dispatcher.handle(frame(2), device: 2)
        dispatcher.handle(frame(4, x: 0.8), device: 1)
        dispatcher.handle(frame(0), device: 2)
        dispatcher.handle(frame(0), device: 1)
        #expect(runner.commands == ["aerospace workspace --wrap-around next"])
    }
}

@Suite struct ShellCommandRunnerTests {
    private func status(of command: String, environment: [String: String] = [:]) async -> Int32 {
        await withCheckedContinuation { continuation in
            ShellCommandRunner(environment: environment).run(command) { continuation.resume(returning: $0) }
        }
    }

    @Test func reportsExitStatus() async {
        #expect(await status(of: "exit 0") == 0)
        #expect(await status(of: "exit 3") == 3)
    }

    @Test func stdinIsATerminal() async {
        #expect(await status(of: "test -t 0") == 0)
    }

    @Test func passesEnvironment() async {
        #expect(await status(of: "test \"$CONGA_TEST\" = yes", environment: ["CONGA_TEST": "yes"]) == 0)
    }

    @Test func runsShellSyntax() async {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("conga-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(await status(of: "echo one > '\(file.path)' && echo two >> '\(file.path)'") == 0)
        #expect(try! String(contentsOf: file, encoding: .utf8) == "one\ntwo\n")
    }

    @Test func loginShellEnvironmentHasUsablePath() {
        let environment = ShellCommandRunner.loginShellEnvironment(base: ["SHELL": "/bin/sh", "KEEP": "1"])
        #expect(environment["KEEP"] == "1")
        #expect(environment["PATH"]?.contains("/usr/bin") == true)
    }

    @Test func loginShellEnvironmentFallsBackWhenShellIsMissing() {
        let environment = ShellCommandRunner.loginShellEnvironment(base: ["SHELL": "/nonexistent/shell", "PATH": "/usr/bin"])
        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin")
    }
}
