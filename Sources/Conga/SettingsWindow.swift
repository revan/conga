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

    /// A threshold expressed in whole percent; edits are re-normalised so the indicator start
    /// always stays below the trigger.
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
            Section("Commands") {
                commandField("Swipe left", text: $model.settings.leftCommand)
                commandField("Swipe right", text: $model.settings.rightCommand)
            }

            Section {
                Toggle("Natural scrolling", isOn: $model.settings.naturalScroll)
            }

            Section("Four-finger swipe distance") {
                thresholdSlider(
                    "Trigger command",
                    value: percent(\.triggerFraction),
                    range: Settings.triggerRange.lowerBound * 100...Settings.triggerRange.upperBound * 100
                )
                thresholdSlider(
                    "Show indicator",
                    value: percent(\.indicatorStartFraction),
                    range: Settings.minimumIndicatorStart * 100...(model.settings.triggerFraction - Settings.minimumSpan) * 100
                )
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

    /// The label sits above the field rather than beside it, so the command gets the full width,
    /// wraps when it is long, and is left-aligned. A right-aligned field hides trailing spaces.
    private func commandField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            TextField(title, text: text, prompt: Text("Shell command"), axis: .vertical)
                .labelsHidden()
                .lineLimit(1...4)
                .multilineTextAlignment(.leading)
                .font(.body.monospaced())
        }
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
