import AppKit
import CongaCore
import os

/// Event taps for what MultitouchSupport cannot do, since it only observes touches.
///
/// The scroll tap keeps scroll and trackpad gesture events from reaching other apps while the
/// workspace overlay is open, because the same fingers also scroll whatever is under the pointer.
///
/// The click tap reports the left button going down and up, so that a swipe made while a click
/// is held can carry the clicked window, and neutralises a carried window's click: its drags are
/// dropped and its mouse-up is delivered outside the window, so the app under it neither
/// follows the seeking fingers nor sees a completed click.
///
/// Both taps run on a thread of their own. While a tap is enabled the window server holds every
/// event it covers until the tap answers, so it must never wait on the main thread, which is
/// busy drawing the overlay at the same time. Each tap is enabled only while it has something
/// to do: the scroll tap while there is something to drop, the click tap while Conga is enabled.
///
/// An event tap that drops events needs Accessibility permission. Without it the taps cannot be
/// created and nothing is blocked or carried; they are created as soon as the permission is
/// granted, or the next time the overlay opens.
final class InputTap: Sendable {
    private struct State {
        var scrolls = ScrollFilter()
        var clicks = ClickFilter()
        var scrollTap: CFMachPort?
        var clickTap: CFMachPort?
        var watchesClicks = false
        /// Where a neutralised click's mouse-up is delivered.
        var dropPoint = CGPoint.zero
        var onClick: (@Sendable (Click) -> Void)?
    }

    enum Click {
        case down(CGPoint)
        /// `moved` says the mouse-up was delivered elsewhere than `location`, where it happened.
        case up(CGPoint, moved: Bool)
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// `NSEvent.EventType` raw values for the trackpad's gesture events, which `CGEventType`
    /// has no cases for: rotate, begin and end gesture, gesture, magnify, swipe, smart magnify.
    private static let gestureTypes: [UInt32] = [18, 19, 20, 29, 30, 31, 32]

    /// Asks for Accessibility permission, with the system's prompt, and creates the taps if it
    /// is already granted. `onClick` is called on the main actor as the left button goes down
    /// and up, while `watchesClicks` is set.
    func start(onClick: @escaping @MainActor (Click) -> Void) {
        state.withLockUnchecked { state in
            state.onClick = { click in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { onClick(click) }
                }
            }
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        NSLog("Conga: Accessibility permission %@", trusted ? "granted" : "not granted")
        installTapsIfNeeded()
        if !trusted {
            // A carry needs the click tap before any overlay opens, so do not wait for one.
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [self] timer in
                guard AXIsProcessTrusted() else { return }
                timer.invalidate()
                NSLog("Conga: Accessibility permission granted")
                installTapsIfNeeded()
            }
        }
    }

    var isBlocking: Bool {
        get { state.withLockUnchecked { $0.scrolls.isBlocking } }
        set {
            if newValue { installTapsIfNeeded() }
            state.withLockUnchecked { state in
                state.scrolls.isBlocking = newValue
                Self.updateTapsEnabled(state)
            }
        }
    }

    var watchesClicks: Bool {
        get { state.withLockUnchecked { $0.watchesClicks } }
        set {
            state.withLockUnchecked { state in
                state.watchesClicks = newValue
                Self.updateTapsEnabled(state)
            }
        }
    }

    /// Neutralises the click being held, delivering its mouse-up at `dropPoint`, unless it has
    /// already become a drag. Returns whether it did.
    func neutraliseClick(dropPoint: CGPoint) -> Bool {
        state.withLockUnchecked { state in
            guard state.clicks.neutralise() else { return false }
            state.dropPoint = dropPoint
            return true
        }
    }

    private func installTapsIfNeeded() {
        guard state.withLockUnchecked({ $0.scrollTap == nil }) else { return }
        var scrollMask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        for type in Self.gestureTypes { scrollMask |= CGEventMask(1) << type }
        let clickMask = [CGEventType.leftMouseDown, .leftMouseDragged, .leftMouseUp]
            .reduce(CGEventMask(0)) { $0 | CGEventMask(1) << $1.rawValue }

        let scrollCallback: CGEventTapCallBack = { _, type, event, userInfo in
            let tap = Unmanaged<InputTap>.fromOpaque(userInfo!).takeUnretainedValue()
            return tap.handleScroll(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        let clickCallback: CGEventTapCallBack = { _, type, event, userInfo in
            let tap = Unmanaged<InputTap>.fromOpaque(userInfo!).takeUnretainedValue()
            return tap.handleClick(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let scrollTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: scrollMask, callback: scrollCallback, userInfo: userInfo
        ), let clickTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: clickMask, callback: clickCallback, userInfo: userInfo
        ) else {
            NSLog("Conga: cannot block scrolling or carry windows without Accessibility permission")
            return
        }
        state.withLockUnchecked { state in
            state.scrollTap = scrollTap
            state.clickTap = clickTap
            Self.updateTapsEnabled(state)
        }
        nonisolated(unsafe) let sources = [scrollTap, clickTap].map { CFMachPortCreateRunLoopSource(nil, $0, 0) }
        let thread = Thread {
            for source in sources { CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes) }
            CFRunLoopRun()
        }
        thread.name = "Conga input tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        NSLog("Conga: event taps installed")
    }

    /// Called on the taps' thread. Returns true if the event should be dropped.
    private func handleScroll(_ type: CGEventType, _ event: CGEvent) -> Bool {
        state.withLockUnchecked { state in
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                NSLog("Conga: scroll event tap was disabled by the system")
                Self.updateTapsEnabled(state)
                return false
            case .scrollWheel:
                let drops = state.scrolls.dropsScroll(
                    phase: Int(event.getIntegerValueField(.scrollWheelEventScrollPhase)),
                    momentumPhase: Int(event.getIntegerValueField(.scrollWheelEventMomentumPhase))
                )
                Self.updateTapsEnabled(state)
                return drops
            default:
                return state.scrolls.dropsGesture()
            }
        }
    }

    /// Called on the taps' thread. Returns true if the event should be dropped; may move a
    /// mouse-up elsewhere.
    private func handleClick(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let (click, drops, onClick): (Click?, Bool, (@Sendable (Click) -> Void)?) = state.withLockUnchecked { state in
            switch type {
            case .leftMouseDown:
                state.clicks.mouseDown(at: event.location)
                return (.down(event.location), false, state.onClick)
            case .leftMouseDragged:
                return (nil, state.clicks.mouseDragged(to: event.location), nil)
            case .leftMouseUp:
                let location = event.location
                let moves = state.clicks.mouseUp()
                if moves { event.location = state.dropPoint }
                return (.up(location, moved: moves), false, state.onClick)
            default:
                NSLog("Conga: click event tap was disabled by the system")
                Self.updateTapsEnabled(state)
                return (nil, false, nil)
            }
        }
        if let click { onClick?(click) }
        return drops
    }

    private static func updateTapsEnabled(_ state: State) {
        if let tap = state.scrollTap { CGEvent.tapEnable(tap: tap, enable: state.scrolls.isActive) }
        if let tap = state.clickTap { CGEvent.tapEnable(tap: tap, enable: state.watchesClicks) }
    }
}
