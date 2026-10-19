import CoreGraphics
import Foundation
import Testing

@testable import CongaCore

private func json(_ windows: [(id: Int, app: String, title: String, workspace: String)]) -> Data {
    let entries = windows.map {
        ["window-id": $0.id, "app-name": $0.app, "window-title": $0.title, "workspace": $0.workspace] as [String: Any]
    }
    return try! JSONSerialization.data(withJSONObject: entries)
}

@Suite struct WorkspaceOverviewTests {
    @Test func groupsWindowsByWorkspaceInNumericOrder() {
        let data = json([
            (1, "Ghostty", "fish", "10"), (2, "Safari", "Apple", "9"), (3, "Ghostty", "vim", "10"), (4, "Mail", "Inbox", "2"),
        ])
        let workspaces = WorkspaceOverview.parse(windowsJSON: data, focusedWorkspace: "")
        #expect(workspaces.map(\.name) == ["2", "9", "10"])
        #expect(workspaces[2].windows == [
            WorkspaceWindow(id: 1, appName: "Ghostty", title: "fish"),
            WorkspaceWindow(id: 3, appName: "Ghostty", title: "vim"),
        ])
    }

    @Test func namedWorkspacesAreLeftOut() {
        let data = json([(1, "Beeper", "Beeper", "beeper"), (2, "Safari", "Apple", "3")])
        #expect(WorkspaceOverview.parse(windowsJSON: data, focusedWorkspace: "beeper").map(\.name) == ["3"])
    }

    @Test func marksTheFocusedWorkspace() {
        let data = json([(1, "A", "a", "1"), (2, "B", "b", "2")])
        let workspaces = WorkspaceOverview.parse(windowsJSON: data, focusedWorkspace: "2\n")
        #expect(workspaces.map(\.isFocused) == [false, true])
    }

    @Test func emptyFocusedWorkspaceIsIncludedIfNumbered() {
        let data = json([(1, "A", "a", "1"), (2, "B", "b", "5")])
        let workspaces = WorkspaceOverview.parse(windowsJSON: data, focusedWorkspace: "3")
        #expect(workspaces.map(\.name) == ["1", "3", "5"])
        #expect(workspaces[1] == Workspace(name: "3", isFocused: true, windows: []))
        #expect(WorkspaceOverview.parse(windowsJSON: data, focusedWorkspace: "beeper").map(\.name) == ["1", "5"])
    }

    @Test func parsesTheCLIsOutput() {
        let data = Data("""
            [
              {
                "app-name" : "Ghostty",
                "window-id" : 19629,
                "window-title" : "~/repo/conga: fish",
                "workspace" : "4"
              }
            ]
            """.utf8)
        #expect(WorkspaceOverview.parse(windowsJSON: data, focusedWorkspace: "4") == [
            Workspace(name: "4", isFocused: true, windows: [
                WorkspaceWindow(id: 19629, appName: "Ghostty", title: "~/repo/conga: fish"),
            ]),
        ])
    }

    @Test func readsTheFocusedWorkspaceFromASubscriptionEvent() {
        let line = #"{"_event":"focused-workspace-changed","prevWorkspace":"1","workspace":"3"}"#
        #expect(WorkspaceOverview.focusedWorkspace(inEvent: line) == "3")
        #expect(WorkspaceOverview.focusedWorkspace(inEvent: #"{"_event":"mode-changed","mode":"main"}"#) == nil)
        #expect(WorkspaceOverview.focusedWorkspace(inEvent: "not json") == nil)
    }

    @Test func refocusMovesTheFocus() {
        let window = WorkspaceWindow(id: 1, appName: "A", title: "a")
        let workspaces = ["1", "2"].map { Workspace(name: $0, isFocused: $0 == "1", windows: [window]) }
        #expect(WorkspaceOverview.refocus(workspaces, on: "2").map(\.isFocused) == [false, true])
    }

    @Test func refocusAddsAndDropsEmptyWorkspacesAsParseWould() {
        let data = json([(1, "A", "a", "2"), (2, "B", "b", "5")])
        for (from, to) in [("3", "7"), ("3", "1"), ("2", "3"), ("3", "5"), ("3", "beeper"), ("beeper", "4")] {
            let refocused = WorkspaceOverview.refocus(WorkspaceOverview.parse(windowsJSON: data, focusedWorkspace: from), on: to)
            #expect(refocused == WorkspaceOverview.parse(windowsJSON: data, focusedWorkspace: to), "\(from) → \(to)")
        }
        #expect(WorkspaceOverview.refocus([], on: "1") == [])
    }

    @Test func unexpectedOutputGivesNoWorkspaces() {
        #expect(WorkspaceOverview.parse(windowsJSON: Data("not json".utf8), focusedWorkspace: "1").isEmpty)
        #expect(WorkspaceOverview.parse(windowsJSON: Data("[]".utf8), focusedWorkspace: "1").isEmpty)
    }

    @Test func untitledWindowIsNamedAfterItsApp() {
        #expect(WorkspaceWindow(id: 1, appName: "Finder", title: " ").displayName == "Finder")
        #expect(WorkspaceWindow(id: 1, appName: "Finder", title: "Downloads").displayName == "Downloads")
    }
}

@Suite struct WorkspaceSeekerTests {
    private func row(_ names: [String], focused: String?) -> [Workspace] {
        names.map { Workspace(name: $0, isFocused: $0 == focused, windows: []) }
    }

    private let step = WorkspaceSeeker.step

    @Test func startsOnTheFocusedWorkspace() {
        var seeker = WorkspaceSeeker()
        #expect(seeker.select(offset: 0, in: row(["1", "2", "3"], focused: "2"))?.name == "2")
    }

    @Test func movesOneWorkspacePerStep() {
        var seeker = WorkspaceSeeker()
        let workspaces = row(["1", "2", "3", "4", "5"], focused: "3")
        #expect(seeker.select(offset: step * 0.4, in: workspaces)?.name == "3")
        #expect(seeker.select(offset: step * 0.6, in: workspaces)?.name == "4")
        #expect(seeker.select(offset: step * 2, in: workspaces)?.name == "5")
        #expect(seeker.select(offset: -step * 2, in: workspaces)?.name == "1")
    }

    @Test func stopsAtTheEnds() {
        var seeker = WorkspaceSeeker()
        let workspaces = row(["1", "2", "3"], focused: "2")
        #expect(seeker.select(offset: step * 5, in: workspaces)?.name == "3")
        #expect(seeker.select(offset: -step * 9, in: workspaces)?.name == "1")
    }

    @Test func turningBackAfterOvershootTakesEffectAtOnce() {
        var seeker = WorkspaceSeeker()
        let workspaces = row(["1", "2", "3"], focused: "2")
        #expect(seeker.select(offset: step * 5, in: workspaces)?.name == "3")
        #expect(seeker.select(offset: step * 4.4, in: workspaces)?.name == "2")
        #expect(seeker.select(offset: step * 3.4, in: workspaces)?.name == "1")
    }

    @Test func withoutAFocusedWorkspaceNothingIsSelectedUntilTheFingersMove() {
        var seeker = WorkspaceSeeker()
        let workspaces = row(["1", "2", "3"], focused: nil)
        #expect(seeker.select(offset: 0, in: workspaces) == nil)
        #expect(seeker.select(offset: step, in: workspaces)?.name == "1")
        #expect(seeker.select(offset: step * 2, in: workspaces)?.name == "2")
        #expect(seeker.select(offset: -step, in: workspaces)?.name == "3")
    }

    @Test func noWorkspacesSelectsNothing() {
        var seeker = WorkspaceSeeker()
        #expect(seeker.select(offset: 0.3, in: []) == nil)
        #expect(seeker.selection(in: []) == nil)
    }

    @Test func selectionFollowsANewRow() {
        var seeker = WorkspaceSeeker()
        _ = seeker.select(offset: step, in: row(["1", "2", "3"], focused: "1"))
        #expect(seeker.selection(in: row(["1", "2", "3"], focused: "2"))?.name == "3")
        #expect(seeker.selection(in: row(["1", "2"], focused: "2"))?.name == "2")
    }

    /// Moves the fingers from 0 to `distance` in `frames` frames, `interval` seconds apart.
    private func seek(
        _ seeker: inout WorkspaceSeeker, to distance: Double, frames: Int, interval: Double,
        in workspaces: [Workspace]
    ) -> Workspace? {
        var selected = seeker.select(offset: 0, timestamp: 0, in: workspaces)
        for frame in 1...frames {
            selected = seeker.select(
                offset: distance * Double(frame) / Double(frames), timestamp: interval * Double(frame), in: workspaces
            )
        }
        return selected
    }

    private let longRow = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]

    @Test func slowMovementIsNotAccelerated() {
        var seeker = WorkspaceSeeker(acceleration: 5)
        // 0.1 trackpad widths a second, under the threshold.
        let selected = seek(&seeker, to: step * 2, frames: 20, interval: 0.1, in: row(longRow, focused: "4"))
        #expect(selected?.name == "6")
    }

    @Test func fastMovementGoesFurther() {
        let workspaces = row(longRow, focused: "4")
        var linear = WorkspaceSeeker()
        var accelerated = WorkspaceSeeker(acceleration: 2)
        // 2 trackpad widths a second.
        #expect(seek(&linear, to: step, frames: 5, interval: 0.01, in: workspaces)?.name == "5")
        #expect(seek(&accelerated, to: step, frames: 5, interval: 0.01, in: workspaces)?.name == "7")
    }

    @Test func moreAccelerationGoesFurtherStill() {
        let workspaces = row(longRow, focused: "1")
        var some = WorkspaceSeeker(acceleration: 1)
        var more = WorkspaceSeeker(acceleration: 4)
        let a = seek(&some, to: step * 2, frames: 10, interval: 0.01, in: workspaces)
        let b = seek(&more, to: step * 2, frames: 10, interval: 0.01, in: workspaces)
        #expect(Int(a!.name)! < Int(b!.name)!)
    }

    @Test func turningBackSlowlyAfterAFastSeekStepsOneAtATime() {
        var seeker = WorkspaceSeeker(acceleration: 2)
        let workspaces = row(longRow, focused: "1")
        let far = seek(&seeker, to: step, frames: 5, interval: 0.01, in: workspaces)
        #expect(far?.name == "4")
        // Back one step at 0.1 widths a second.
        var selected = far
        for frame in 1...10 {
            selected = seeker.select(offset: step - 0.01 * Double(frame), timestamp: 0.05 + 0.1 * Double(frame), in: workspaces)
        }
        #expect(selected?.name == "3")
    }

    @Test func gainIsCapped() {
        var seeker = WorkspaceSeeker(acceleration: 5)
        let workspaces = row(longRow + ["10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20"], focused: "1")
        // An absurd 50 widths a second for a tenth of the width.
        let selected = seek(&seeker, to: step, frames: 2, interval: 0.001, in: workspaces)
        #expect(Int(selected!.name)! <= 1 + Int(WorkspaceSeeker.maximumGain))
    }

    @Test func negativeAccelerationIsNone() {
        #expect(WorkspaceSeeker(acceleration: -3).acceleration == 0)
    }

    @Test func switchCommandNamesTheWorkspace() {
        #expect(WorkspaceOverview.switchCommand(to: "7") == "aerospace workspace 7")
    }
}

@Suite struct WorkspaceOverviewLayoutTests {
    @Test func squaresKeepPreferredSizeWhenTheyFit() {
        #expect(WorkspaceOverviewLayout.squareSize(count: 3, available: 1000, preferred: 200, spacing: 16) == 200)
    }

    @Test func squaresShrinkToFit() {
        let size = WorkspaceOverviewLayout.squareSize(count: 6, available: 1000, preferred: 200, spacing: 20)
        #expect(size == 150)
        #expect(WorkspaceOverviewLayout.squareSize(count: 0, available: 1000, preferred: 200, spacing: 20) == 0)
    }

    @Test(arguments: [1, 2, 3, 5, 9, 10]) func thumbnailsStayInBoundsWithoutOverlapping(count: Int) {
        let bounds = CGRect(x: 10, y: 10, width: 180, height: 180)
        let frames = WorkspaceOverviewLayout.thumbnailFrames(count: count, in: bounds, spacing: 6)
        #expect(frames.count == count)
        for (index, frame) in frames.enumerated() {
            #expect(frame.width > 0 && frame.height > 0)
            #expect(bounds.insetBy(dx: -1e-9, dy: -1e-9).contains(frame))
            for other in frames[(index + 1)...] {
                #expect(!frame.insetBy(dx: 1e-9, dy: 1e-9).intersects(other))
            }
        }
    }

    @Test func oneThumbnailFillsTheBounds() {
        let bounds = CGRect(x: 10, y: 10, width: 180, height: 180)
        #expect(WorkspaceOverviewLayout.thumbnailFrames(count: 1, in: bounds, spacing: 6) == [bounds])
    }

    @Test func thumbnailsRunFromTheTopAndCentreAShortLastRow() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let frames = WorkspaceOverviewLayout.thumbnailFrames(count: 3, in: bounds, spacing: 10)
        #expect(frames[0] == CGRect(x: 0, y: 55, width: 45, height: 45))
        #expect(frames[1] == CGRect(x: 55, y: 55, width: 45, height: 45))
        #expect(frames[2] == CGRect(x: 27.5, y: 0, width: 45, height: 45))
    }

    @Test func aspectFitCentresInTheCell() {
        let cell = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(WorkspaceOverviewLayout.aspectFit(CGSize(width: 400, height: 200), in: cell)
            == CGRect(x: 0, y: 25, width: 100, height: 50))
        #expect(WorkspaceOverviewLayout.aspectFit(CGSize(width: 100, height: 400), in: cell)
            == CGRect(x: 37.5, y: 0, width: 25, height: 100))
        #expect(WorkspaceOverviewLayout.aspectFit(.zero, in: cell) == cell)
    }
}
