import AppKit
import CongaCore
import SwiftUI

// SwiftUI has its own `Settings` scene type.
typealias Settings = CongaCore.Settings

@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: Settings {
        didSet {
            if settings != oldValue { onChange?(settings) }
        }
    }

    var onChange: ((Settings) -> Void)?

    init(settings: Settings) {
        self.settings = settings
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    /// A threshold expressed in whole percent; edits are re-normalised so the fade-in start
    /// always stays below the full overlay.
    private func percent(_ keyPath: WritableKeyPath<Settings, Double>) -> Binding<Double> {
        Binding {
            (model.settings[keyPath: keyPath] * 100).rounded()
        } set: { value in
            var settings = model.settings
            settings[keyPath: keyPath] = value / 100
            model.settings = settings.normalized()
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Natural scrolling", isOn: $model.settings.naturalScroll)
            }

            Section {
                thresholdSlider(
                    "Show overlay",
                    value: percent(\.triggerFraction),
                    range: Settings.triggerRange.lowerBound * 100...Settings.triggerRange.upperBound * 100
                )
                thresholdSlider(
                    "Start fading in",
                    value: percent(\.indicatorStartFraction),
                    range: Settings.minimumIndicatorStart * 100...(model.settings.triggerFraction - Settings.minimumSpan) * 100
                )
            } header: {
                Text("Four-finger swipe distance")
            } footer: {
                Text("A sideways swipe shows the overlay in \(Int((Settings.sidewaysTriggerScale * 100).rounded()))% of this distance.")
                    .foregroundStyle(.secondary)
            }

            Section("Workspace overlay") {
                LabeledContent("Acceleration") {
                    HStack {
                        Slider(
                            value: $model.settings.workspaceAcceleration,
                            in: Settings.accelerationRange,
                            step: 0.5
                        )
                        Text(model.settings.workspaceAcceleration == 0
                            ? "Off"
                            : model.settings.workspaceAcceleration.formatted(.number.precision(.fractionLength(1))))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    var defaults = Settings()
                    defaults.isEnabled = model.settings.isEnabled
                    model.settings = defaults
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func thresholdSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range, step: 1)
                Text("\(Int(value.wrappedValue))%")
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)
            }
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    init(model: SettingsModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Conga Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
