import AppKit
import SlideCore

/// The arrow-in-a-glass-box HUD. Its opacity and arrow position follow gesture progress
/// directly; only what happens after release is a timed animation.
@MainActor
final class IndicatorWindow {
    private static let size: CGFloat = 200
    private static let cornerRadius: CGFloat = 28
    /// How far from centre the arrow starts.
    private static let arrowTravel: CGFloat = 46
    private static let bottomMargin: CGFloat = 140
    private static let fadeOutDuration = 0.25
    /// Time for the arrow to slide the full travel back to the edge after an aborted swipe.
    private static let retreatDuration = 0.1

    private let panel: NSPanel
    private let arrow = NSImageView()
    private var arrowCenterX: NSLayoutConstraint!
    private var shownDirection: SwipeDirection?
    /// Bumped on every show so a stale fade-out completion does not hide a newer gesture.
    private var generation = 0

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
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

        let content = NSView()
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 84, weight: .medium)
        content.addSubview(arrow)
        arrowCenterX = arrow.centerXAnchor.constraint(equalTo: content.centerXAnchor)
        NSLayoutConstraint.activate([arrowCenterX, arrow.centerYAnchor.constraint(equalTo: content.centerYAnchor)])

        panel.contentView = Self.makeBackground(containing: content)
    }

    private static func makeBackground(containing content: NSView) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        content.frame = effect.bounds
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return effect
    }

    func apply(_ update: IndicatorUpdate) {
        switch update {
        case .show(let direction, let progress):
            show(direction, progress: progress)
        case .hide(let fired):
            hide(fired: fired)
        }
    }

    private func show(_ direction: SwipeDirection, progress: Double) {
        let layout = IndicatorModel.layout(direction: direction, progress: progress, travel: Self.arrowTravel)
        generation += 1

        guard layout.opacity > 0 else {
            panel.alphaValue = 0
            panel.orderOut(nil)
            return
        }

        if shownDirection != direction {
            shownDirection = direction
            arrow.image = NSImage(
                systemSymbolName: direction == .left ? "arrow.left" : "arrow.right",
                accessibilityDescription: nil
            )
        }
        arrow.contentTintColor = layout.isArmed ? .labelColor : .secondaryLabelColor
        arrowCenterX.constant = layout.arrowOffset

        if !panel.isVisible {
            positionOnActiveScreen()
            panel.orderFrontRegardless()
        }
        panel.alphaValue = layout.opacity
    }

    private func hide(fired: Bool) {
        guard panel.isVisible else { return }
        generation += 1
        let generation = generation

        guard !fired, let direction = shownDirection else {
            fadeOut(generation: generation)
            return
        }

        // An aborted swipe first slides the arrow back to the edge it came from, then fades.
        let edge = IndicatorModel.layout(direction: direction, progress: 0, travel: Self.arrowTravel).arrowOffset
        let distance = abs(edge - arrowCenterX.constant) / Self.arrowTravel
        arrow.contentTintColor = .secondaryLabelColor
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.retreatDuration * distance
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            arrowCenterX.animator().constant = edge
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.fadeOut(generation: generation)
            }
        }
    }

    private func fadeOut(generation: Int) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == generation else { return }
                self.panel.orderOut(nil)
            }
        }
    }

    /// Centred horizontally near the bottom of the screen under the pointer.
    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let frame = screen.frame
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size / 2, y: frame.minY + Self.bottomMargin))
    }
}
