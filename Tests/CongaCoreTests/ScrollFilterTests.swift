import Testing

@testable import CongaCore

@Suite struct ScrollFilterTests {
    private let began = 1, changed = 2, ended = 4
    private let momentumBegin = 1, momentumContinue = 2, momentumEnd = 3

    /// Feeds `events`, as (phase, momentum phase), and returns which were dropped.
    private func drops(_ filter: inout ScrollFilter, _ events: [(Int, Int)]) -> [Bool] {
        events.map { filter.dropsScroll(phase: $0.0, momentumPhase: $0.1) }
    }

    @Test func passesEverythingWhenNotBlocking() {
        var filter = ScrollFilter()
        let dropped = drops(&filter, [(began, 0), (changed, 0), (0, momentumContinue)])
        #expect(dropped == [false, false, false])
        #expect(!filter.dropsGesture())
        #expect(!filter.isActive)
    }

    @Test func dropsEverythingWhileBlocking() {
        var filter = ScrollFilter()
        filter.isBlocking = true
        #expect(drops(&filter, [(began, 0), (changed, 0), (0, 0)]) == [true, true, true])
        #expect(filter.dropsGesture())
    }

    @Test func dropsTheRestOfTheScrollAndItsMomentumAfterUnblocking() {
        var filter = ScrollFilter()
        filter.isBlocking = true
        filter.isBlocking = false
        #expect(!filter.dropsGesture())
        let dropped = drops(&filter, [
            (changed, 0), (ended, 0), (0, momentumBegin), (0, momentumContinue), (0, momentumEnd),
        ])
        #expect(dropped == [true, true, true, true, true])
        #expect(filter.isActive)
    }

    @Test func aNewScrollEndsTheDrain() {
        var filter = ScrollFilter()
        filter.isBlocking = true
        filter.isBlocking = false
        let dropped = drops(&filter, [(0, momentumContinue), (ScrollFilter.phaseMayBegin, 0), (changed, 0)])
        #expect(dropped == [true, false, false])
        #expect(!filter.isActive)
    }

    @Test func aMouseWheelEndsTheDrain() {
        var filter = ScrollFilter()
        filter.isBlocking = true
        filter.isBlocking = false
        #expect(drops(&filter, [(0, 0), (changed, 0)]) == [false, false])
    }

    @Test func unblockingWhenNotBlockedDrainsNothing() {
        var filter = ScrollFilter()
        filter.isBlocking = false
        #expect(drops(&filter, [(changed, 0)]) == [false])
    }
}
