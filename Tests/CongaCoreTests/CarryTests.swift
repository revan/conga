import CoreGraphics
import Testing

@testable import CongaCore

private final class RecordingRunner: CommandRunning {
    var commands: [String] = []
    func run(_ command: String) { commands.append(command) }
}

/// The finger holding the click, near the bottom of the trackpad.
private let anchor = Touch(id: 50, x: 0.5, y: 0.1)

/// `frame` with the clicking finger still down.
private func holding(_ frame: TouchFrame) -> TouchFrame {
    TouchFrame(timestamp: frame.timestamp, touches: frame.touches + [anchor])
}

/// The window being carried, on the focused workspace.
private let window = 7

@Suite struct CarryTests {
    private final class Updates {
        var values: [IndicatorUpdate] = []
    }

    private static let workspaces = ["1", "2", "3", "4"].map {
        Workspace(name: $0, isFocused: $0 == "2", windows: $0 == "2" ? [WorkspaceWindow(id: window, appName: "", title: "")] : [])
    }

    /// A dispatcher with the click already held on `window`.
    private func makeHeld(carrying: Int? = window) -> (GestureDispatcher, RecordingRunner, Updates, Asked) {
        let runner = RecordingRunner()
        let dispatcher = GestureDispatcher(settings: Settings(), runner: runner)
        dispatcher.workspaces = Self.workspaces
        let updates = Updates()
        dispatcher.onIndicatorUpdate = { updates.values.append($0) }
        let asked = Asked()
        dispatcher.carryWindow = {
            asked.count += 1
            return carrying
        }
        dispatcher.handle(TouchFrame(touches: [anchor]))
        dispatcher.clickBegan()
        return (dispatcher, runner, updates, asked)
    }

    private final class Asked {
        var count = 0
    }

    private func selections(_ updates: [IndicatorUpdate]) -> [String?] {
        updates.compactMap { if case .showWorkspaces(_, let selected, _) = $0 { selected } else { nil } }
    }

    /// Swipes right with four more fingers to workspace 3, then lifts them.
    private func swipeToThree(_ dispatcher: GestureDispatcher) {
        for f in [frame(4), frame(4, x: 0.6), frame(4, x: 0.71), frame(0)] { dispatcher.handle(holding(f)) }
    }

    @Test func releasingTheClickAfterTheFingersLiftMovesTheWindow() {
        let (dispatcher, runner, updates, _) = makeHeld()
        swipeToThree(dispatcher)
        #expect(selections(updates.values) == ["2", "3"])
        #expect(updates.values.last == .showWorkspaces(progress: 1, selected: "3", carrying: window))
        #expect(runner.commands.isEmpty)

        dispatcher.clickEnded()
        #expect(runner.commands == ["aerospace move-node-to-workspace --window-id 7 --focus-follows-window 3"])
        #expect(updates.values.last == .hide)
    }

    @Test func fingersPutDownAgainSeekOnFromTheSelection() {
        let (dispatcher, runner, updates, _) = makeHeld()
        swipeToThree(dispatcher)
        let before = updates.values.count
        for f in [frame(4, x: 0.2), frame(4, x: 0.31), frame(0)] { dispatcher.handle(holding(f)) }
        #expect(updates.values.dropFirst(before).map { $0 } == [
            .showWorkspaces(progress: 1, selected: "3", carrying: window),
            .showWorkspaces(progress: 1, selected: "4", carrying: window),
        ])
        dispatcher.clickEnded()
        #expect(runner.commands == ["aerospace move-node-to-workspace --window-id 7 --focus-follows-window 4"])
    }

    @Test func releasingTheClickWithTheFingersDownLeavesTheWindow() {
        let (dispatcher, runner, updates, _) = makeHeld()
        for f in [frame(4), frame(4, x: 0.6), frame(4, x: 0.71)] { dispatcher.handle(holding(f)) }
        dispatcher.clickEnded()
        #expect(updates.values.last == .hide)
        let count = updates.values.count
        // The fingers carry on moving and lift: nothing more happens.
        for f in [frame(4, x: 0.85), frame(0)] { dispatcher.handle(f) }
        #expect(updates.values.count == count)
        #expect(runner.commands.isEmpty)
    }

    @Test func droppingOnTheWindowsOwnWorkspaceRunsNothing() {
        let (dispatcher, runner, updates, _) = makeHeld()
        for f in [frame(4), frame(4, x: 0.6), frame(0)] { dispatcher.handle(holding(f)) }
        dispatcher.clickEnded()
        #expect(runner.commands.isEmpty)
        #expect(updates.values.last == .hide)
    }

    @Test func swipeCancelledBeforeTheOverlayIsFullyShownEndsTheCarry() {
        let (dispatcher, runner, updates, _) = makeHeld()
        for f in [frame(4), frame(4, x: 0.57), frame(0)] { dispatcher.handle(holding(f)) }
        #expect(updates.values.last == .hide)
        let count = updates.values.count
        dispatcher.clickEnded()
        #expect(updates.values.count == count)
        #expect(runner.commands.isEmpty)
    }

    @Test func withNothingToCarryTheSwipeSwitchesAsUsual() {
        let (dispatcher, runner, updates, _) = makeHeld(carrying: nil)
        swipeToThree(dispatcher)
        #expect(runner.commands == ["aerospace workspace 3"])
        #expect(updates.values.last == .hide)
        dispatcher.clickEnded()
        #expect(runner.commands == ["aerospace workspace 3"])
    }

    @Test func theWindowIsAskedForOncePerClick() {
        let (dispatcher, _, _, asked) = makeHeld()
        swipeToThree(dispatcher)
        for f in [frame(4), frame(4, x: 0.6), frame(0)] { dispatcher.handle(holding(f)) }
        #expect(asked.count == 1)
        dispatcher.clickEnded()
        dispatcher.clickBegan()
        for f in [frame(4), frame(0)] { dispatcher.handle(holding(f)) }
        #expect(asked.count == 2)
    }

    @Test func withoutAClickTheWindowIsNeverAskedFor() {
        let (dispatcher, _, _, asked) = makeHeld()
        dispatcher.clickEnded()
        for f in [frame(4), frame(4, x: 0.71), frame(0)] { dispatcher.handle(f) }
        #expect(asked.count == 0)
    }
}

@Suite struct StartsSeekingTests {
    private let thresholds = GestureThresholds(lowerBound: 0.05, trigger: 0.20)

    @Test func fourFingersSeekAtOnce() {
        var recognizer = GestureRecognizer()
        recognizer.startsSeeking = true
        #expect(recognizer.handle(frame(4), thresholds: thresholds) == .peek(fraction: 1, offset: 0))
        let moved = recognizer.handle(frame(4, x: 0.53), thresholds: thresholds)
        guard case .peek(1, let offset) = moved else {
            Issue.record("expected a peek, got \(String(describing: moved))")
            return
        }
        #expect(abs(offset - 0.03) < 1e-9)
        #expect(recognizer.handle(frame(0), thresholds: thresholds) == .peekReleased)
    }

    @Test func endingIgnoresTheRestOfTheGesture() {
        var recognizer = GestureRecognizer()
        _ = recognizer.handle(frame(4), thresholds: thresholds)
        _ = recognizer.handle(frame(4, x: 0.7), thresholds: thresholds)
        recognizer.end()
        #expect(recognizer.handle(frame(4, x: 0.9), thresholds: thresholds) == nil)
        #expect(recognizer.handle(frame(0), thresholds: thresholds) == nil)
        #expect(recognizer.handle(frame(4), thresholds: thresholds) == nil)
        #expect(recognizer.handle(frame(4, x: 0.7), thresholds: thresholds) != nil)
    }
}

@Suite struct ClickFilterTests {
    @Test func passesEverythingUnlessNeutralised() {
        var filter = ClickFilter()
        filter.mouseDown(at: CGPoint(x: 10, y: 10))
        let result1 = filter.mouseDragged(to: CGPoint(x: 50, y: 10))
        #expect(!result1)
        let result2 = filter.mouseUp()
        #expect(!result2)
    }

    @Test func neutralisedClickDropsDragsAndMovesItsMouseUp() {
        var filter = ClickFilter()
        filter.mouseDown(at: CGPoint(x: 10, y: 10))
        let result3 = filter.mouseDragged(to: CGPoint(x: 12, y: 11))
        #expect(!result3)
        let result4 = filter.neutralise()
        #expect(result4)
        let result5 = filter.mouseDragged(to: CGPoint(x: 80, y: 10))
        #expect(result5)
        let result6 = filter.mouseUp()
        #expect(result6)
        // The next click is left alone.
        filter.mouseDown(at: CGPoint(x: 10, y: 10))
        let result7 = filter.mouseDragged(to: CGPoint(x: 80, y: 10))
        #expect(!result7)
        let result8 = filter.mouseUp()
        #expect(!result8)
    }

    @Test func aClickThatBecameADragIsNeverNeutralised() {
        var filter = ClickFilter()
        filter.mouseDown(at: CGPoint(x: 10, y: 10))
        _ = filter.mouseDragged(to: CGPoint(x: 15, y: 10))
        _ = filter.mouseDragged(to: CGPoint(x: 11, y: 10))
        let result9 = filter.neutralise()
        #expect(!result9)
        let result10 = filter.mouseUp()
        #expect(!result10)
    }

    @Test func nothingToNeutraliseWithTheButtonUp() {
        var filter = ClickFilter()
        let result11 = filter.neutralise()
        #expect(!result11)
        filter.mouseDown(at: .zero)
        _ = filter.mouseUp()
        let result12 = filter.neutralise()
        #expect(!result12)
    }
}

@Test func moveWindowCommandFollowsTheWindow() {
    #expect(
        WorkspaceOverview.moveWindowCommand(12, to: "5")
            == "aerospace move-node-to-workspace --window-id 12 --focus-follows-window 5"
    )
}
