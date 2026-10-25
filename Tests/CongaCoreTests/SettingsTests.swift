import Foundation
import Testing

@testable import CongaCore

@Suite struct SettingsTests {
    /// A store backed by a throwaway defaults domain.
    private func withStore(_ body: (SettingsStore) -> Void) {
        let suite = "CongaTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(SettingsStore(defaults: defaults))
    }

    @Test func defaults() {
        withStore { store in
            let settings = store.load()
            #expect(settings.isEnabled)
            #expect(!settings.naturalScroll)
            #expect(settings.triggerFraction == 0.20)
            #expect(settings.indicatorStartFraction == 0.05)
            #expect(settings.workspaceAcceleration == 1.5)
        }
    }

    @Test func roundTrip() {
        withStore { store in
            var settings = Settings()
            settings.isEnabled = false
            settings.naturalScroll = true
            settings.triggerFraction = 0.4
            settings.indicatorStartFraction = 0.1
            settings.workspaceAcceleration = 3.5
            store.save(settings)
            #expect(store.load() == settings)
        }
    }

    @Test func thresholdsMirrorFractions() {
        var settings = Settings()
        settings.triggerFraction = 0.3
        settings.indicatorStartFraction = 0.1
        #expect(settings.thresholds == GestureThresholds(lowerBound: 0.1, trigger: 0.3, sidewaysTrigger: 0.15))
    }

    @Test func sidewaysTriggerIsNeverBelowTheIndicatorStart() {
        var settings = Settings()
        settings.triggerFraction = 0.1
        settings.indicatorStartFraction = 0.08
        #expect(settings.thresholds.sidewaysTrigger == 0.08)
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
        settings.workspaceAcceleration = 99
        let normalized = settings.normalized()
        #expect(normalized.triggerFraction == Settings.triggerRange.upperBound)
        #expect(normalized.indicatorStartFraction == Settings.minimumIndicatorStart)
        #expect(normalized.workspaceAcceleration == Settings.accelerationRange.upperBound)
        settings.workspaceAcceleration = -1
        #expect(settings.normalized().workspaceAcceleration == 0)
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
