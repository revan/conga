import CoreGraphics
import Foundation

public struct WorkspaceWindow: Equatable, Sendable {
    /// The window server's ID for the window, which is also AeroSpace's.
    public var id: Int
    public var appName: String
    public var title: String

    public init(id: Int, appName: String, title: String) {
        self.id = id
        self.appName = appName
        self.title = title
    }

    /// What to show in place of a preview: the title, or the app's name for an untitled window.
    public var displayName: String {
        title.allSatisfy(\.isWhitespace) ? appName : title
    }
}

public struct Workspace: Equatable, Sendable {
    public var name: String
    public var isFocused: Bool
    public var windows: [WorkspaceWindow]

    public init(name: String, isFocused: Bool, windows: [WorkspaceWindow]) {
        self.name = name
        self.isFocused = isFocused
        self.windows = windows
    }
}

/// Which windows are on which workspace, according to the `aerospace` CLI.
public enum WorkspaceOverview {
    public static let listWindowsCommand =
        "aerospace list-windows --all --json --format '%{window-id}%{app-name}%{window-title}%{workspace}'"
    public static let focusedWorkspaceCommand = "aerospace list-workspaces --focused"

    private struct Entry: Decodable {
        var id: Int
        var appName: String?
        var title: String?
        var workspace: String

        enum CodingKeys: String, CodingKey {
            case id = "window-id"
            case appName = "app-name"
            case title = "window-title"
            case workspace
        }
    }

    /// The numbered workspaces that have windows, in numeric order. Workspaces with other
    /// names are left out, and so are empty ones, which `list-windows` never mentions.
    /// Output that is not the expected JSON gives an empty list.
    public static func parse(windowsJSON: Data, focusedWorkspace: String) -> [Workspace] {
        guard let entries = try? JSONDecoder().decode([Entry].self, from: windowsJSON) else { return [] }
        let focused = focusedWorkspace.trimmingCharacters(in: .whitespacesAndNewlines)

        var windows: [Int: [WorkspaceWindow]] = [:]
        var names: [Int: String] = [:]
        for entry in entries {
            guard let number = Int(entry.workspace) else { continue }
            names[number] = entry.workspace
            windows[number, default: []].append(
                WorkspaceWindow(id: entry.id, appName: entry.appName ?? "", title: entry.title ?? "")
            )
        }
        return windows.keys.sorted().map { number in
            let name = names[number] ?? String(number)
            return Workspace(name: name, isFocused: name == focused, windows: windows[number] ?? [])
        }
    }
}

/// Geometry of the overlay: a row of squares, each with its windows tiled in a grid. The
/// windows' real positions are no use, because AeroSpace parks the windows of hidden
/// workspaces off-screen.
public enum WorkspaceOverviewLayout {
    /// The side of each square: `preferred`, or less if `count` squares `spacing` apart would
    /// not fit in `available`.
    public static func squareSize(count: Int, available: Double, preferred: Double, spacing: Double) -> Double {
        guard count > 0 else { return 0 }
        let fitting = (available - spacing * Double(count - 1)) / Double(count)
        return max(min(preferred, fitting), 0)
    }

    /// Cells for `count` windows inside `bounds`, in rows from the top (y points up, as in
    /// AppKit). A last row that is not full is centred.
    public static func thumbnailFrames(count: Int, in bounds: CGRect, spacing: Double) -> [CGRect] {
        guard count > 0 else { return [] }
        let columns = Int(Double(count).squareRoot().rounded(.up))
        let rows = (count + columns - 1) / columns
        let width = (bounds.width - spacing * Double(columns - 1)) / Double(columns)
        let height = (bounds.height - spacing * Double(rows - 1)) / Double(rows)

        return (0..<count).map { index in
            let row = index / columns
            let column = index % columns
            let inRow = row == rows - 1 ? count - row * columns : columns
            let rowWidth = Double(inRow) * width + Double(inRow - 1) * spacing
            return CGRect(
                x: bounds.midX - rowWidth / 2 + Double(column) * (width + spacing),
                y: bounds.maxY - Double(row + 1) * height - Double(row) * spacing,
                width: width,
                height: height
            )
        }
    }

    /// The largest rect with the proportions of `size` that fits in `cell`, centred in it.
    public static func aspectFit(_ size: CGSize, in cell: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return cell }
        let scale = min(cell.width / size.width, cell.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(x: cell.midX - width / 2, y: cell.midY - height / 2, width: width, height: height)
    }
}
