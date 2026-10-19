import Foundation
import os
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

    @Test func fingersMovingLeftSwipeRight() {
        let (dispatcher, runner, updates) = makeDispatcher()
        for f in [frame(4), frame(4, x: 0.2), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands == ["aerospace workspace --wrap-around next"])
        #expect(updates() == [.show(.right, progress: 1), .hide(fired: true)])
    }

    @Test func fingersMovingRightSwipeLeft() {
        let (dispatcher, runner, updates) = makeDispatcher()
        for f in [frame(4), frame(4, x: 0.8), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands == ["aerospace workspace --wrap-around prev"])
        #expect(updates() == [.show(.left, progress: 1), .hide(fired: true)])
    }

    @Test func withoutNaturalScrollSwipeFollowsFingers() {
        var settings = Settings()
        settings.naturalScroll = false
        let (dispatcher, runner, updates) = makeDispatcher(settings)
        for f in [frame(4), frame(4, x: 0.8), frame(0)] { dispatcher.handle(f) }
        for f in [frame(4), frame(4, x: 0.2), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands == ["aerospace workspace --wrap-around next", "aerospace workspace --wrap-around prev"])
        #expect(updates() == [
            .show(.right, progress: 1), .hide(fired: true),
            .show(.left, progress: 1), .hide(fired: true),
        ])
    }

    @Test func reversedSwipeRunsNothing() {
        let (dispatcher, runner, updates) = makeDispatcher()
        for f in [frame(4), frame(4, x: 0.8), frame(4, x: 0.5), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands.isEmpty)
        #expect(updates() == [.show(.left, progress: 1), .show(.left, progress: 0), .hide(fired: false)])
    }

    @Test func customCommandsAndThresholdsApplyLive() {
        let (dispatcher, runner, _) = makeDispatcher()
        var settings = Settings()
        settings.leftCommand = "echo hi"
        settings.triggerFraction = 0.5
        dispatcher.settings = settings

        for f in [frame(4), frame(4, x: 0.8), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands.isEmpty)
        for f in [frame(4, x: 0.2), frame(4, x: 0.8), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands == ["echo hi"])
    }

    @Test func blankCommandIsNotRun() {
        var settings = Settings()
        settings.leftCommand = "  "
        let (dispatcher, runner, updates) = makeDispatcher(settings)
        for f in [frame(4), frame(4, x: 0.8), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands.isEmpty)
        #expect(updates().last == .hide(fired: true))
    }

    private static let workspaces = ["1", "2", "3", "4"].map {
        Workspace(name: $0, isFocused: $0 == "2", windows: [])
    }

    @Test func swipeUpSelectsFocusedWorkspaceAndReleasingRunsNothing() {
        let (dispatcher, runner, updates) = makeDispatcher()
        dispatcher.workspaces = Self.workspaces
        for f in [frame(4), frame(4, y: 0.52), frame(4, y: 0.9), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands.isEmpty)
        #expect(updates() == [
            .show(.left, progress: 0), .showWorkspaces(progress: 1, selected: "2"), .hide(fired: true),
        ])
    }

    @Test func movingSidewaysSeeksAndReleasingSwitches() {
        let (dispatcher, runner, updates) = makeDispatcher()
        dispatcher.workspaces = Self.workspaces
        for f in [frame(4), frame(4, y: 0.9), frame(4, x: 0.61, y: 0.9), frame(4, x: 0.71, y: 0.9), frame(0)] {
            dispatcher.handle(f)
        }
        #expect(updates() == [
            .showWorkspaces(progress: 1, selected: "2"), .showWorkspaces(progress: 1, selected: "3"),
            .showWorkspaces(progress: 1, selected: "4"), .hide(fired: true),
        ])
        #expect(runner.commands == ["aerospace workspace 4"])
    }

    @Test func fastSeekingIsAcceleratedByTheSetting() {
        func switched(acceleration: Double) -> [String] {
            var settings = Settings()
            settings.workspaceAcceleration = acceleration
            let (dispatcher, runner, _) = makeDispatcher(settings)
            dispatcher.workspaces = ["1", "2", "3", "4", "5", "6"].map {
                Workspace(name: $0, isFocused: $0 == "1", windows: [])
            }
            let frames = [frame(4), frame(4, y: 0.9)] + (1...6).map { frame(4, x: 0.5 + 0.02 * Double($0), y: 0.9) }
            for (index, f) in frames.enumerated() {
                var f = f
                f.timestamp = 0.01 * Double(index)
                dispatcher.handle(f)
            }
            dispatcher.handle(frame(0))
            return runner.commands
        }
        #expect(switched(acceleration: 0) == ["aerospace workspace 2"])
        #expect(switched(acceleration: 3) != ["aerospace workspace 2"])
    }

    @Test func seekingIgnoresNaturalScroll() {
        var settings = Settings()
        settings.naturalScroll = false
        let (dispatcher, runner, _) = makeDispatcher(settings)
        dispatcher.workspaces = Self.workspaces
        for f in [frame(4), frame(4, y: 0.9), frame(4, x: 0.39, y: 0.9), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands == ["aerospace workspace 1"])
    }

    @Test func swipingBackDownAfterSeekingSwitchesNothing() {
        let (dispatcher, runner, updates) = makeDispatcher()
        dispatcher.workspaces = Self.workspaces
        for f in [frame(4), frame(4, y: 0.9), frame(4, x: 0.61, y: 0.9), frame(4, x: 0.61, y: 0.52), frame(0)] {
            dispatcher.handle(f)
        }
        #expect(runner.commands.isEmpty)
        #expect(updates().last == .hide(fired: false))
    }

    @Test func releaseUsesWorkspacesAsTheyAreNow() {
        let (dispatcher, runner, _) = makeDispatcher()
        dispatcher.workspaces = Self.workspaces
        for f in [frame(4), frame(4, y: 0.9), frame(4, x: 0.61, y: 0.9)] { dispatcher.handle(f) }
        // A refresh arrives mid-gesture: workspace 3 turns out to be the focused one.
        dispatcher.workspaces = ["1", "3", "5"].map { Workspace(name: $0, isFocused: $0 == "3", windows: []) }
        dispatcher.handle(frame(0))
        #expect(runner.commands == ["aerospace workspace 5"])
    }

    @Test func eachSwipeUpStartsFromTheFocusedWorkspace() {
        let (dispatcher, runner, updates) = makeDispatcher()
        dispatcher.workspaces = Self.workspaces
        for f in [frame(4), frame(4, y: 0.9), frame(4, x: 0.61, y: 0.9), frame(0)] { dispatcher.handle(f) }
        for f in [frame(4), frame(4, y: 0.9), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands == ["aerospace workspace 3"])
        #expect(updates().suffix(2) == [.showWorkspaces(progress: 1, selected: "2"), .hide(fired: true)])
    }

    @Test func swipeUpWithNoWorkspacesSelectsNothing() {
        let (dispatcher, runner, updates) = makeDispatcher()
        for f in [frame(4), frame(4, y: 0.9), frame(4, x: 0.8, y: 0.9), frame(0)] { dispatcher.handle(f) }
        #expect(runner.commands.isEmpty)
        #expect(updates().first == .showWorkspaces(progress: 1, selected: nil))
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
        #expect(runner.commands == ["aerospace workspace --wrap-around prev"])
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

    @Test func outputIsWhatTheCommandPrinted() async {
        let output = await ShellCommandRunner(environment: [:]).output(of: "echo one; echo two")
        #expect(output == Data("one\ntwo\n".utf8))
    }

    @Test func outputLargerThanAPipeBufferIsReadWhole() async {
        let output = await ShellCommandRunner(environment: [:]).output(of: "/usr/bin/head -c 300000 /dev/zero")
        #expect(output?.count == 300_000)
    }

    @Test func outputIsNilWhenTheCommandFails() async {
        #expect(await ShellCommandRunner(environment: [:]).output(of: "echo partial; exit 2") == nil)
    }

    @Test func outputCommandHasATerminalForStdin() async {
        let output = await ShellCommandRunner(environment: [:]).output(of: "test -t 0 && echo yes")
        #expect(output == Data("yes\n".utf8))
    }

    @Test func linesArriveOneByOne() async {
        let lines = OSAllocatedUnfairLock<[String]>(initialState: [])
        let status = await withCheckedContinuation { continuation in
            ShellCommandRunner(environment: [:]).lines(of: "echo one; printf 'two\\nthree'") { line in
                lines.withLock { $0.append(line) }
            } completion: { continuation.resume(returning: $0) }
        }
        #expect(status == 0)
        // The last line has no newline; it is complete when the output ends, which may be
        // after the command exits.
        try? await Task.sleep(for: .milliseconds(100))
        #expect(lines.withLock { $0 } == ["one", "two", "three"])
    }

    @Test func linesArriveWhileTheCommandRunsAndItCanBeStopped() async {
        let (lines, linesContinuation) = AsyncStream.makeStream(of: String.self)
        let (exit, exitContinuation) = AsyncStream.makeStream(of: Int32.self)
        let command = ShellCommandRunner(environment: [:]).lines(of: "echo ready; exec sleep 10") {
            linesContinuation.yield($0)
        } completion: {
            exitContinuation.yield($0)
        }
        var iterator = lines.makeAsyncIterator()
        #expect(await iterator.next() == "ready")
        command?.terminate()
        var exits = exit.makeAsyncIterator()
        let status = await exits.next()
        #expect(status != nil && status != 0)
    }

    @Test func lineSplitterWaitsForTheNewline() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("{\"a\":".utf8)) == [])
        #expect(splitter.append(Data("1}\r\n{\"b\"".utf8)) == ["{\"a\":1}"])
        #expect(splitter.append(Data(":2}\n\n".utf8)) == ["{\"b\":2}", ""])
        #expect(splitter.append(Data("tail".utf8)) == [])
        #expect(splitter.append(Data()) == ["tail"])
        #expect(splitter.append(Data()) == [])
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
