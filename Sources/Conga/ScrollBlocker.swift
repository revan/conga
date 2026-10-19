import AppKit
import CongaCore
import os

/// Keeps scroll and trackpad gesture events from reaching other apps while the workspace
/// overlay is open. MultitouchSupport only observes touches, so the same fingers also scroll
/// whatever is under the pointer; an event tap is the only place to take those events away.
///
/// The tap runs on a thread of its own. While it is enabled the window server holds every
/// scroll event until the tap answers, so it must never wait on the main thread, which is busy
/// drawing the overlay at the same time.
///
/// An event tap that drops events needs Accessibility permission. Without it the tap cannot be
/// created, nothing is blocked, and creating it is tried again on the next swipe up.
final class ScrollBlocker: Sendable {
    private struct State {
        var filter = ScrollFilter()
        var tap: CFMachPort?
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// `NSEvent.EventType` raw values for the trackpad's gesture events, which `CGEventType`
    /// has no cases for: rotate, begin and end gesture, gesture, magnify, swipe, smart magnify.
    private static let gestureTypes: [UInt32] = [18, 19, 20, 29, 30, 31, 32]

    /// Asks for Accessibility permission, with the system's prompt, and creates the tap if it
    /// is already granted.
    func start() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        NSLog("Conga: Accessibility permission %@", trusted ? "granted" : "not granted")
        installTapIfNeeded()
    }

    var isBlocking: Bool {
        get { state.withLockUnchecked { $0.filter.isBlocking } }
        set {
            if newValue { installTapIfNeeded() }
            state.withLockUnchecked { state in
                state.filter.isBlocking = newValue
                Self.updateTapEnabled(state)
            }
        }
    }

    private func installTapIfNeeded() {
        guard state.withLockUnchecked({ $0.tap == nil }) else { return }
        var mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
        for type in Self.gestureTypes { mask |= CGEventMask(1) << type }
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            let blocker = Unmanaged<ScrollBlocker>.fromOpaque(userInfo!).takeUnretainedValue()
            return blocker.handle(type, event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Conga: cannot block scrolling under the overlay without Accessibility permission")
            return
        }
        state.withLockUnchecked { state in
            state.tap = tap
            Self.updateTapEnabled(state)
        }
        nonisolated(unsafe) let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        let thread = Thread {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "Conga scroll blocker"
        thread.qualityOfService = .userInteractive
        thread.start()
        NSLog("Conga: scroll event tap installed")
    }

    /// Called on the tap's thread. Returns true if the event should be dropped.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        state.withLockUnchecked { state in
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                NSLog("Conga: scroll event tap was disabled by the system")
                Self.updateTapEnabled(state)
                return false
            case .scrollWheel:
                let drops = state.filter.dropsScroll(
                    phase: Int(event.getIntegerValueField(.scrollWheelEventScrollPhase)),
                    momentumPhase: Int(event.getIntegerValueField(.scrollWheelEventMomentumPhase))
                )
                Self.updateTapEnabled(state)
                return drops
            default:
                return state.filter.dropsGesture()
            }
        }
    }

    /// The tap only runs while there is something to drop, so that ordinary scrolling never
    /// waits on this app.
    private static func updateTapEnabled(_ state: State) {
        guard let tap = state.tap else { return }
        CGEvent.tapEnable(tap: tap, enable: state.filter.isActive)
    }
}
