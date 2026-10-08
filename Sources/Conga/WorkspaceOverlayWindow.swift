import AppKit
import CongaCore

/// The row of workspace squares shown while swiping up. Like the arrow box, its opacity
/// follows gesture progress directly, and it fades out on release.
@MainActor
final class WorkspaceOverlayWindow {
    private static let spacing: CGFloat = 16
    /// Space kept clear at each side of the screen.
    private static let sideMargin: CGFloat = 40
    /// Padding around the window tiles in a square of the full size, and the gap between them.
    private static let tileInset: CGFloat = 14
    private static let tileSpacing: CGFloat = 6

    private let panel = HUDStyle.makePanel(size: NSSize(width: HUDStyle.size, height: HUDStyle.size))
    private var workspaces: [Workspace] = []
    private var previews: [Int: CGImage] = [:]
    /// The progress last asked for; 0 once hidden.
    private var progress = 0.0
    private var needsRebuild = true
    /// Bumped on every show so a stale fade-out completion does not hide a newer gesture.
    private var generation = 0

    func show(progress: Double) {
        self.progress = min(max(progress, 0), 1)
        generation += 1
        refresh()
    }

    /// Replaces what the overlay shows, including while it is on screen.
    func update(workspaces: [Workspace], previews: [Int: CGImage]) {
        self.workspaces = workspaces
        self.previews = previews
        needsRebuild = true
        refresh()
    }

    func hide() {
        progress = 0
        guard panel.isVisible else { return }
        generation += 1
        let generation = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = HUDStyle.fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func refresh() {
        guard progress > 0, !workspaces.isEmpty else {
            // Nothing to show yet, or not asked to. A fade-out in progress is left alone.
            if progress > 0 || !panel.isVisible { panel.orderOut(nil) }
            return
        }
        if needsRebuild || !panel.isVisible {
            rebuild()
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        panel.alphaValue = progress
    }

    /// Lays the squares out in a row, centred near the bottom of the screen under the pointer.
    private func rebuild() {
        guard let screen = HUDStyle.activeScreen()?.frame else { return }
        needsRebuild = false

        let count = workspaces.count
        let size = WorkspaceOverviewLayout.squareSize(
            count: count,
            available: screen.width - 2 * Self.sideMargin,
            preferred: HUDStyle.size,
            spacing: Self.spacing
        )
        let width = CGFloat(count) * size + CGFloat(count - 1) * Self.spacing

        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: size))
        for (index, workspace) in workspaces.enumerated() {
            let square = HUDStyle.makeBackground(containing: makeContent(for: workspace, size: size), size: size)
            square.setFrameOrigin(NSPoint(x: CGFloat(index) * (size + Self.spacing), y: 0))
            row.addSubview(square)
        }
        panel.contentView = row
        panel.setFrame(
            NSRect(x: screen.midX - width / 2, y: screen.minY + HUDStyle.bottomMargin, width: width, height: size),
            display: true
        )
    }

    /// The workspace's number with its windows tiled over it.
    private func makeContent(for workspace: Workspace, size: CGFloat) -> NSView {
        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        let scale = size / HUDStyle.size
        let content = NSView(frame: bounds)

        let number = NSTextField(labelWithString: workspace.name)
        number.font = .systemFont(ofSize: 84 * scale, weight: .medium)
        number.textColor = workspace.isFocused ? .labelColor : .secondaryLabelColor
        number.sizeToFit()
        number.setFrameOrigin(NSPoint(x: bounds.midX - number.frame.width / 2, y: bounds.midY - number.frame.height / 2))
        content.addSubview(number)

        let cells = WorkspaceOverviewLayout.thumbnailFrames(
            count: workspace.windows.count,
            in: bounds.insetBy(dx: Self.tileInset * scale, dy: Self.tileInset * scale),
            spacing: Self.tileSpacing * scale
        )
        for (window, cell) in zip(workspace.windows, cells) {
            content.addSubview(makeTile(for: window, in: cell))
        }
        return content
    }

    /// A preview of the window fitted into `cell`, or its name if there is no preview.
    private func makeTile(for window: WorkspaceWindow, in cell: CGRect) -> NSView {
        if let preview = previews[window.id] {
            let size = NSSize(width: preview.width, height: preview.height)
            let view = NSImageView(frame: WorkspaceOverviewLayout.aspectFit(size, in: cell))
            view.image = NSImage(cgImage: preview, size: size)
            view.imageScaling = .scaleAxesIndependently
            view.wantsLayer = true
            view.layer?.cornerRadius = 4
            view.layer?.masksToBounds = true
            return view
        }

        let tile = NSView(frame: cell)
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 6
        tile.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor

        let name = NSTextField(wrappingLabelWithString: window.displayName)
        name.font = .systemFont(ofSize: 11, weight: .medium)
        name.textColor = .white
        name.alignment = .center
        name.maximumNumberOfLines = 2
        name.cell?.truncatesLastVisibleLine = true
        name.cell?.lineBreakMode = .byTruncatingTail
        let padding: CGFloat = 4
        let fitting = name.sizeThatFits(NSSize(width: cell.width - 2 * padding, height: cell.height))
        let height = min(fitting.height, cell.height)
        name.frame = NSRect(x: padding, y: (cell.height - height) / 2, width: cell.width - 2 * padding, height: height)
        tile.addSubview(name)
        return tile
    }
}
