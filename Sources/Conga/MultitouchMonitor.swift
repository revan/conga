import AppKit
import CMultitouch
import CongaCore

/// Set before any device is started and only read from the framework's callback thread.
nonisolated(unsafe) private var frameHandler: (@Sendable (Int, TouchFrame) -> Void)?

private let contactCallback: MTContactCallbackFunction = { device, touches, count, timestamp, _ in
    var result: [Touch] = []
    if let touches {
        for touch in UnsafeBufferPointer(start: touches, count: Int(count)) {
            // BreakTouch is included so the final frame of a lifting finger still counts as down.
            guard (MTTouchStateMakeTouch...MTTouchStateBreakTouch).contains(Int(touch.state)) else { continue }
            let position = touch.normalized.position
            result.append(Touch(id: Int(touch.identifier), x: Double(position.x), y: Double(position.y)))
        }
    }
    frameHandler?(Int(bitPattern: device), TouchFrame(timestamp: timestamp, touches: result))
    return 0
}

/// Streams raw touch frames from every trackpad via the private MultitouchSupport framework.
@MainActor
final class MultitouchMonitor {
    private var deviceList: CFArray?
    private var devices: [MTDeviceRef] = []
    private var wakeObserver: NSObjectProtocol?

    /// Calls `handler` on the main actor with a device identifier and each frame, in order.
    /// Returns false if no trackpad was found.
    @discardableResult
    func start(handler: @escaping @MainActor (Int, TouchFrame) -> Void) -> Bool {
        frameHandler = { device, frame in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { handler(device, frame) }
            }
        }
        // Devices stop reporting after sleep until they are restarted.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopDevices()
                self?.startDevices()
            }
        }
        return startDevices()
    }

    @discardableResult
    private func startDevices() -> Bool {
        guard let list = MTDeviceCreateList()?.takeRetainedValue() else { return false }
        deviceList = list
        devices = (0..<CFArrayGetCount(list)).compactMap { index in
            UnsafeMutableRawPointer(mutating: CFArrayGetValueAtIndex(list, index))
        }
        for device in devices {
            MTRegisterContactFrameCallback(device, contactCallback)
            MTDeviceStart(device, 0)
        }
        NSLog("Conga: listening to %d multitouch device(s)", devices.count)
        return !devices.isEmpty
    }

    private func stopDevices() {
        for device in devices {
            MTUnregisterContactFrameCallback(device, contactCallback)
            MTDeviceStop(device)
        }
        devices = []
        deviceList = nil
    }
}
