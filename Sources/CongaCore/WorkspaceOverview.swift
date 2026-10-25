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
    /// AeroSpace's ID for the monitor the workspace is on, if known.
    public var monitor: Int?

    public init(name: String, isFocused: Bool, windows: [WorkspaceWindow], monitor: Int? = nil) {
        self.name = name
        self.isFocused = isFocused
        self.windows = windows
        self.monitor = monitor
    }
}

/// Which windows are on which workspace, according to the `aerospace` CLI.
public enum WorkspaceOverview {
    public static let listWindowsCommand =
        "aerospace list-windows --all --json --format '%{window-id}%{app-name}%{window-title}%{workspace}'"
    public static let focusedWorkspaceCommand = "aerospace list-workspaces --focused"
    /// Every workspace with the monitor it is on, for `monitors(inJSON:)`.
    public static let monitorsCommand = "aerospace list-workspaces --all --json --format '%{workspace}%{monitor-id}'"
    /// Prints a line of JSON when it starts and again every time the focused workspace changes.
    /// AeroSpace has had `subscribe` since 0.21; older versions fail it.
    public static let subscribeToFocusCommand = "aerospace subscribe focused-workspace-changed"

    public static func switchCommand(to workspace: String) -> String {
        "aerospace workspace \(workspace)"
    }

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

    private struct MonitorEntry: Decodable {
        var workspace: String
        var monitor: Int

        enum CodingKeys: String, CodingKey {
            case workspace
            case monitor = "monitor-id"
        }
    }

    /// The monitor each workspace is on, by workspace name, from `monitorsCommand`'s output.
    /// Output that is not the expected JSON gives none.
    public static func monitors(inJSON data: Data) -> [String: Int] {
        guard let entries = try? JSONDecoder().decode([MonitorEntry].self, from: data) else { return [:] }
        return Dictionary(entries.map { ($0.workspace, $0.monitor) }) { first, _ in first }
    }

    /// The numbered workspaces that have windows, and the focused one if it is numbered,
    /// grouped by monitor in the order of their IDs, and in numeric order within a monitor.
    /// Workspaces on no monitor in `monitors` come last. Workspaces with other names are left
    /// out, and so are other empty ones, which `list-windows` never mentions. Output that is
    /// not the expected JSON gives an empty list.
    public static func parse(windowsJSON: Data, focusedWorkspace: String, monitors: [String: Int] = [:]) -> [Workspace] {
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
        if let number = Int(focused), !entries.isEmpty, windows[number] == nil {
            names[number] = focused
            windows[number] = []
        }
        return windows.keys.map { number in
            let name = names[number] ?? String(number)
            return Workspace(name: name, isFocused: name == focused, windows: windows[number] ?? [], monitor: monitors[name])
        }
        .sorted { rowOrder($0) < rowOrder($1) }
    }

    /// Sorts numbered workspaces into the overlay's row.
    private static func rowOrder(_ workspace: Workspace) -> (Int, Int) {
        (workspace.monitor ?? .max, Int(workspace.name) ?? .max)
    }
}

extension WorkspaceOverview {
    private struct FocusEvent: Decodable {
        var workspace: String
    }

    /// The workspace that a line from `subscribeToFocusCommand` says is now focused.
    public static func focusedWorkspace(inEvent line: String) -> String? {
        try? JSONDecoder().decode(FocusEvent.self, from: Data(line.utf8)).workspace
    }

    /// `workspaces` as `parse` would have given them had `focused` been the focused workspace:
    /// an empty workspace is there only while it is focused. `monitors` says where to put a
    /// workspace that was not in the list.
    public static func refocus(_ workspaces: [Workspace], on focused: String, monitors: [String: Int] = [:]) -> [Workspace] {
        guard !workspaces.isEmpty else { return [] }
        var result = workspaces
            .filter { !$0.windows.isEmpty || $0.name == focused }
            .map { Workspace(name: $0.name, isFocused: $0.name == focused, windows: $0.windows, monitor: $0.monitor) }
        if Int(focused) != nil, !result.contains(where: \.isFocused) {
            let added = Workspace(name: focused, isFocused: true, windows: [], monitor: monitors[focused])
            let index = result.firstIndex { rowOrder($0) > rowOrder(added) } ?? result.endIndex
            result.insert(added, at: index)
        }
        return result
    }
}

/// Picks a workspace from how far the fingers have moved sideways during one swipe up: the
/// focused workspace to begin with, and one further along the row for every `step`.
///
/// With acceleration, sideways movement counts for more the faster the fingers go, like the
/// pointer: a slow movement moves the selection one workspace at a time, a quick one jumps
/// several. Each frame's movement is multiplied by `1 + acceleration × speed`, the speed in
/// trackpad widths per second above `speedThreshold`, smoothed over a few frames.
///
/// The row does not wrap. Moving past either end drags the starting point along, so that
/// turning back takes effect at once, as it does for a swipe.
public struct WorkspaceSeeker: Sendable {
    /// Sideways travel, as a fraction of trackpad width, that moves the selection by one.
    public static let step = 0.10
    /// Speeds below this, in trackpad widths per second, are not accelerated, so that slow,
    /// deliberate seeking stays one workspace per step.
    public static let speedThreshold = 0.2
    /// The most a frame's movement is multiplied by, however fast the fingers go.
    public static let maximumGain = 8.0
    /// How long, in seconds, the speed takes to follow the fingers. Single frames are noisy.
    public static let smoothing = 0.04

    public let acceleration: Double

    private var origin = 0.0
    /// The sideways travel so far, accelerated.
    private var position = 0.0
    private var last: (offset: Double, timestamp: Double)?
    private var speed = 0.0

    public init(acceleration: Double = 0) {
        self.acceleration = max(acceleration, 0)
    }

    /// Selects a workspace for fingers `offset` from where the swipe started, at `timestamp`
    /// seconds.
    public mutating func select(offset: Double, timestamp: Double = 0, in workspaces: [Workspace]) -> Workspace? {
        advance(to: offset, at: timestamp)
        guard let limits = Self.limits(in: workspaces) else { return nil }
        let steps = rawSteps
        if steps < limits.lowerBound {
            origin = position - Double(limits.lowerBound) * Self.step
        } else if steps > limits.upperBound {
            origin = position - Double(limits.upperBound) * Self.step
        }
        return selection(in: workspaces)
    }

    private mutating func advance(to offset: Double, at timestamp: Double) {
        defer { last = (offset, timestamp) }
        guard let last else {
            position = offset
            return
        }
        let delta = offset - last.offset
        let elapsed = timestamp - last.timestamp
        if elapsed > 0 {
            let weight = min(elapsed / Self.smoothing, 1)
            speed += (abs(delta) / elapsed - speed) * weight
        }
        let gain = min(1 + acceleration * max(speed - Self.speedThreshold, 0), Self.maximumGain)
        position += delta * gain
    }

    /// The workspace that the last offset selects among `workspaces`.
    public func selection(in workspaces: [Workspace]) -> Workspace? {
        guard let limits = Self.limits(in: workspaces) else { return nil }
        let steps = min(max(rawSteps, limits.lowerBound), limits.upperBound)
        if let focused = workspaces.firstIndex(where: \.isFocused) {
            return workspaces[focused + steps]
        }
        // The focused workspace is not in the row: come in from the end the fingers left.
        if steps == 0 { return nil }
        return workspaces[steps > 0 ? steps - 1 : workspaces.count + steps]
    }

    private var rawSteps: Int {
        Int(((position - origin) / Self.step).rounded())
    }

    /// How many steps there are to each end of the row.
    private static func limits(in workspaces: [Workspace]) -> ClosedRange<Int>? {
        guard !workspaces.isEmpty else { return nil }
        if let focused = workspaces.firstIndex(where: \.isFocused) {
            return -focused...(workspaces.count - 1 - focused)
        }
        return -workspaces.count...workspaces.count
    }
}

/// Geometry of the overlay: a row of squares, each with its windows tiled in a grid. The
/// windows' real positions are no use, because AeroSpace parks the windows of hidden
/// workspaces off-screen.
public enum WorkspaceOverviewLayout {
    /// The indices of the workspaces that start a new monitor's group in the row, where the
    /// row leaves a gap. A workspace whose monitor is unknown starts no group.
    public static func monitorBreaks(in workspaces: [Workspace]) -> Set<Int> {
        Set(workspaces.indices.dropFirst().filter { index in
            guard let monitor = workspaces[index].monitor, let previous = workspaces[index - 1].monitor else {
                return false
            }
            return monitor != previous
        })
    }

    /// The side of each square: `preferred`, or less if `count` squares `spacing` apart, with
    /// `breaks` of them half a square further from the one before, would not fit in `available`.
    public static func squareSize(
        count: Int,
        breaks: Int = 0,
        available: Double,
        preferred: Double,
        spacing: Double
    ) -> Double {
        guard count > 0 else { return 0 }
        let fitting = (available - spacing * Double(count - 1)) / (Double(count) + Double(breaks) / 2)
        return max(min(preferred, fitting), 0)
    }

    /// Where each of `count` squares of side `size` starts along the row, and the row's width:
    /// `spacing` apart, plus half a square before each index in `breaks`.
    public static func squareOffsets(
        count: Int,
        breaks: Set<Int>,
        size: Double,
        spacing: Double
    ) -> (offsets: [Double], width: Double) {
        var offsets: [Double] = []
        var x = 0.0
        for index in 0..<count {
            if index > 0 { x += spacing }
            if breaks.contains(index) { x += size / 2 }
            offsets.append(x)
            x += size
        }
        return (offsets, x)
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
