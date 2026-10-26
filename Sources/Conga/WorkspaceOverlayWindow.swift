import AppKit
import CongaCore

/// The row of workspace squares shown while swiping up or sideways. Its opacity follows
/// gesture progress directly, and it fades out on release.
@MainActor
final class WorkspaceOverlayWindow {
    private static let spacing: CGFloat = 16
    /// Space kept clear at each side of the screen.
    private static let sideMargin: CGFloat = 40
    /// Padding around the window tiles in a square of the full size, and the gap between them.
    private static let tileInset: CGFloat = 14
    private static let tileSpacing: CGFloat = 6
    private static let outlineWidth: CGFloat = 5
    private static let outlineMoveDuration = 0.12
    /// A carried window's preview fits in this fraction of a square, this far above the row.
    private static let liftedScale: CGFloat = 0.8
    private static let liftedGap: CGFloat = 12

    private let panel = HUDStyle.makePanel(size: NSSize(width: HUDStyle.size, height: HUDStyle.size))
    private let outline = NSView()
    private var workspaces: [Workspace] = []
    /// Where each workspace's square is in the row, by name.
    private var squareFrames: [String: NSRect] = [:]
    private var selected: String?
    private var previews: [Int: CGImage] = [:]
    /// The window being carried to another workspace, shown above the outline instead of
    /// in its square.
    private var carrying: Int?
    /// The carried window's preview, and the size it is fitted to, while there is one.
    private var lifted: NSView?
    private var liftedSize = CGSize.zero
    /// The progress last asked for; 0 once hidden.
    private var progress = 0.0
    private var needsRebuild = true
    /// Bumped on every show so a stale fade-out completion does not hide a newer gesture.
    private var generation = 0

    init() {
        outline.wantsLayer = true
        outline.layer?.borderWidth = Self.outlineWidth
        outline.layer?.cornerCurve = .continuous
    }

    /// `selected` names the workspace to outline, if any; `carrying` is the window being
    /// carried, if any.
    func show(progress: Double, selected: String?, carrying: Int? = nil) {
        // Changes to the outline animate only once the overlay is up; it appears in place.
        let wasShown = self.progress > 0 && panel.isVisible
        self.progress = min(max(progress, 0), 1)
        if carrying != self.carrying {
            self.carrying = carrying
            needsRebuild = true
        }
        generation += 1
        refresh()
        select(selected, animated: wasShown)
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
        if carrying != nil {
            carrying = nil
            needsRebuild = true
        }
        // Forget it, so the next gesture does not briefly outline where this one ended.
        selected = nil
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
            select(selected, animated: false)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        panel.alphaValue = progress
    }

    /// Puts the outline around the selected workspace's square, sliding it there if it was
    /// already around another, or fading it in there if it was around none.
    private func select(_ name: String?, animated: Bool) {
        let frame = name.flatMap { squareFrames[$0] }
        let wasHidden = outline.isHidden
        let changed = selected != name
        selected = name
        outline.isHidden = frame == nil
        lifted?.isHidden = frame == nil
        guard let frame, changed || !animated else { return }
        let liftedOrigin = WorkspaceOverviewLayout.liftedFrame(
            liftedSize, over: frame, scale: Self.liftedScale, gap: Self.liftedGap
        ).origin

        // Resolved here rather than once, so it follows the accent colour and appearance.
        outline.layer?.borderColor = NSColor.controlAccentColor.cgColor
        guard animated && panel.isVisible else {
            outline.frame = frame
            outline.alphaValue = 1
            lifted?.setFrameOrigin(liftedOrigin)
            return
        }
        if wasHidden {
            outline.frame = frame
            outline.alphaValue = 0
            lifted?.setFrameOrigin(liftedOrigin)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.outlineMoveDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            outline.animator().frame = frame
            outline.animator().alphaValue = 1
            lifted?.animator().setFrameOrigin(liftedOrigin)
        }
    }

    /// Lays the squares out in a row, centred near the bottom of the screen under the pointer.
    private func rebuild() {
        guard let screen = HUDStyle.activeScreen()?.frame else { return }
        needsRebuild = false

        // Each monitor's workspaces are a group of their own, set apart by half a square.
        let breaks = WorkspaceOverviewLayout.monitorBreaks(in: workspaces)
        let size = WorkspaceOverviewLayout.squareSize(
            count: workspaces.count,
            breaks: breaks.count,
            available: screen.width - 2 * Self.sideMargin,
            preferred: HUDStyle.size,
            spacing: Self.spacing
        )
        let (offsets, width) = WorkspaceOverviewLayout.squareOffsets(
            count: workspaces.count, breaks: breaks, size: size, spacing: Self.spacing
        )

        // Room above the row for a carried window's preview.
        let carried = carrying.flatMap { id in workspaces.lazy.flatMap(\.windows).first { $0.id == id } }
        let height = carried == nil ? size : size + Self.liftedGap + size * Self.liftedScale
        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        squareFrames = [:]
        for (workspace, offset) in zip(workspaces, offsets) {
            let square = HUDStyle.makeBackground(containing: makeContent(for: workspace, size: size), size: size)
            square.setFrameOrigin(NSPoint(x: offset, y: 0))
            row.addSubview(square)
            squareFrames[workspace.name] = square.frame
        }
        outline.layer?.cornerRadius = HUDStyle.cornerRadius * size / HUDStyle.size
        row.addSubview(outline)
        lifted = carried.map { window in
            let view = makeLifted(window, squareSize: size)
            row.addSubview(view)
            return view
        }
        panel.contentView = row
        panel.setFrame(
            NSRect(x: screen.midX - width / 2, y: screen.minY + HUDStyle.bottomMargin, width: width, height: height),
            display: true
        )
    }

    /// The workspace's windows tiled, with its number drawn over them.
    private func makeContent(for workspace: Workspace, size: CGFloat) -> NSView {
        let bounds = NSRect(x: 0, y: 0, width: size, height: size)
        let scale = size / HUDStyle.size
        let content = NSView(frame: bounds)

        // The carried window is shown above the outline instead.
        let windows = workspace.windows.filter { $0.id != carrying }
        let cells = WorkspaceOverviewLayout.thumbnailFrames(
            count: windows.count,
            in: bounds.insetBy(dx: Self.tileInset * scale, dy: Self.tileInset * scale),
            spacing: Self.tileSpacing * scale
        )
        for (window, cell) in zip(windows, cells) {
            content.addSubview(makeTile(for: window, in: cell))
        }

        let number = NSTextField(labelWithString: workspace.name)
        number.font = .systemFont(ofSize: 84 * scale, weight: .medium)
        number.sizeToFit()
        number.setFrameOrigin(NSPoint(x: bounds.midX - number.frame.width / 2, y: bounds.midY - number.frame.height / 2))
        if windows.isEmpty {
            number.textColor = workspace.isFocused ? .labelColor : .secondaryLabelColor
        } else {
            // White with a shadow stays readable over light and dark previews alike.
            number.textColor = .white.withAlphaComponent(workspace.isFocused ? 1 : 0.75)
            let shadow = NSShadow()
            shadow.shadowColor = .black.withAlphaComponent(0.6)
            shadow.shadowBlurRadius = 6 * scale
            number.shadow = shadow
        }
        content.addSubview(number)
        return content
    }

    /// The carried window's preview, or its name in a tile, with a shadow to lift it off the
    /// row. `select` puts it in place.
    private func makeLifted(_ window: WorkspaceWindow, squareSize: CGFloat) -> NSView {
        let source = previews[window.id].map { CGSize(width: $0.width, height: $0.height) } ?? CGSize(width: 16, height: 10)
        let frame = WorkspaceOverviewLayout.liftedFrame(
            source, over: CGRect(x: 0, y: 0, width: squareSize, height: squareSize),
            scale: Self.liftedScale, gap: 0
        )
        liftedSize = frame.size
        let container = NSView(frame: NSRect(origin: .zero, size: frame.size))
        container.wantsLayer = true
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.5
        container.layer?.shadowRadius = 12
        container.layer?.shadowOffset = CGSize(width: 0, height: -4)
        container.addSubview(makeTile(for: window, in: container.bounds))
        return container
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
