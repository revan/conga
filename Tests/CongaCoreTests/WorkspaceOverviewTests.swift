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

    @Test func unexpectedOutputGivesNoWorkspaces() {
        #expect(WorkspaceOverview.parse(windowsJSON: Data("not json".utf8), focusedWorkspace: "1").isEmpty)
        #expect(WorkspaceOverview.parse(windowsJSON: Data("[]".utf8), focusedWorkspace: "1").isEmpty)
    }

    @Test func untitledWindowIsNamedAfterItsApp() {
        #expect(WorkspaceWindow(id: 1, appName: "Finder", title: " ").displayName == "Finder")
        #expect(WorkspaceWindow(id: 1, appName: "Finder", title: "Downloads").displayName == "Downloads")
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
