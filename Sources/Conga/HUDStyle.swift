import AppKit

/// What the arrow box and the workspace overlay have in common.
@MainActor
enum HUDStyle {
    /// Side of the arrow box, and of a workspace square when there is room.
    static let size: CGFloat = 200
    /// Corner radius of a box of that size; smaller boxes scale it down.
    static let cornerRadius: CGFloat = 28
    static let bottomMargin: CGFloat = 140
    static let fadeOutDuration = 0.25

    /// A transparent, click-through panel above everything, on every space, starting hidden.
    static func makePanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.alphaValue = 0
        return panel
    }

    /// A glass square of side `size` with `content` filling it.
    static func makeBackground(containing content: NSView, size: CGFloat) -> NSView {
        let frame = NSRect(x: 0, y: 0, width: size, height: size)
        let radius = cornerRadius * size / Self.size
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.cornerRadius = radius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = radius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }

    /// The screen under the pointer.
    static func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}
