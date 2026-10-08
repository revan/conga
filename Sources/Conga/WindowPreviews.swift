import CoreGraphics
import ScreenCaptureKit

enum WindowPreviews {
    /// Images of the given windows, at most `maxPixelSize` pixels on the longer side. A window
    /// that cannot be captured is left out; without Screen Recording permission that is all
    /// of them.
    static func capture(windowIDs: [Int], maxPixelSize: Int) async -> [Int: CGImage] {
        guard CGPreflightScreenCaptureAccess(),
              // Not only on-screen windows: AeroSpace keeps hidden workspaces' windows off-screen.
              let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        else { return [:] }

        let wanted = Set(windowIDs)
        var images: [Int: CGImage] = [:]
        for window in content.windows where wanted.contains(Int(window.windowID)) {
            let longer = max(window.frame.width, window.frame.height)
            guard longer > 0 else { continue }
            let scale = min(CGFloat(maxPixelSize) / longer, 2)
            let configuration = SCStreamConfiguration()
            configuration.width = max(Int(window.frame.width * scale), 1)
            configuration.height = max(Int(window.frame.height * scale), 1)
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: window)
            if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) {
                images[Int(window.windowID)] = image
            }
        }
        return images
    }
}
