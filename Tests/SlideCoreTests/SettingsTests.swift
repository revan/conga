import Foundation
import Testing

@testable import SlideCore

@Suite struct SettingsTests {
    /// A store backed by a throwaway defaults domain.
    private func withStore(_ body: (SettingsStore) -> Void) {
        let suite = "SlideTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(SettingsStore(defaults: defaults))
    }

    @Test func defaults() {
        withStore { store in
            let settings = store.load()
            #expect(settings.isEnabled)
            #expect(settings.leftCommand == "aerospace workspace --wrap-around prev")
            #expect(settings.rightCommand == "aerospace workspace --wrap-around next")
            #expect(settings.triggerFraction == 0.20)
            #expect(settings.indicatorStartFraction == 0.05)
        }
    }

    @Test func roundTrip() {
        withStore { store in
            var settings = Settings()
            settings.isEnabled = false
            settings.leftCommand = "echo left"
            settings.rightCommand = "echo right"
            settings.triggerFraction = 0.4
            settings.indicatorStartFraction = 0.1
            store.save(settings)
            #expect(store.load() == settings)
        }
    }

    @Test func commandForDirection() {
        let settings = Settings()
        #expect(settings.command(for: .left) == settings.leftCommand)
        #expect(settings.command(for: .right) == settings.rightCommand)
    }

    @Test func thresholdsMirrorFractions() {
        var settings = Settings()
        settings.triggerFraction = 0.3
        settings.indicatorStartFraction = 0.1
        #expect(settings.thresholds == GestureThresholds(lowerBound: 0.1, trigger: 0.3))
    }

    @Test func indicatorStartIsKeptBelowTrigger() {
        var settings = Settings()
        settings.triggerFraction = 0.10
        settings.indicatorStartFraction = 0.50
        let normalized = settings.normalized()
        #expect(normalized.triggerFraction == 0.10)
        #expect(normalized.indicatorStartFraction < normalized.triggerFraction)
    }

    @Test func outOfRangeValuesAreClamped() {
        var settings = Settings()
        settings.triggerFraction = 5
        settings.indicatorStartFraction = -1
        let normalized = settings.normalized()
        #expect(normalized.triggerFraction == Settings.triggerRange.upperBound)
        #expect(normalized.indicatorStartFraction == Settings.minimumIndicatorStart)
    }

    @Test func loadNormalizesStoredValues() {
        withStore { store in
            var settings = Settings()
            settings.triggerFraction = 0.2
            settings.indicatorStartFraction = 0.9
            store.save(settings)
            #expect(store.load().indicatorStartFraction < 0.2)
        }
    }
}
