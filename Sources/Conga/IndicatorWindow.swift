import AppKit
import CongaCore

/// The arrow-in-a-glass-box HUD. Its opacity and arrow position follow gesture progress
/// directly; only what happens after release is a timed animation.
@MainActor
final class IndicatorWindow {
    private static let size = HUDStyle.size
    /// How far from centre the arrow starts.
    private static let arrowTravel: CGFloat = 46
    /// Time for the arrow to slide the full travel back to the edge after an aborted swipe.
    private static let retreatDuration = 0.1

    private let panel: NSPanel
    private let arrow = NSImageView()
    private var arrowCenterX: NSLayoutConstraint!
    private var shownDirection: SwipeDirection?
    /// Bumped on every show so a stale fade-out completion does not hide a newer gesture.
    private var generation = 0

    init() {
        panel = HUDStyle.makePanel(size: NSSize(width: Self.size, height: Self.size))

        let content = NSView()
        arrow.translatesAutoresizingMaskIntoConstraints = false
        arrow.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 84, weight: .medium)
        content.addSubview(arrow)
        arrowCenterX = arrow.centerXAnchor.constraint(equalTo: content.centerXAnchor)
        NSLayoutConstraint.activate([arrowCenterX, arrow.centerYAnchor.constraint(equalTo: content.centerYAnchor)])

        panel.contentView = HUDStyle.makeBackground(containing: content, size: Self.size)
    }

    func show(_ direction: SwipeDirection, progress: Double) {
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

    func hide(fired: Bool) {
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
            context.duration = HUDStyle.fadeOutDuration
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
        guard let frame = HUDStyle.activeScreen()?.frame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.midX - Self.size / 2, y: frame.minY + HUDStyle.bottomMargin))
    }
}
