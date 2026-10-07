import Testing

@testable import CongaCore

@Suite struct IndicatorModelTests {
    @Test func hiddenAtEdgeWhenProgressIsZero() {
        let layout = IndicatorModel.layout(direction: .right, progress: 0, travel: 50)
        #expect(layout == IndicatorLayout(opacity: 0, arrowOffset: -50, isArmed: false))
    }

    @Test func opaqueAndCentredAtFullProgress() {
        let layout = IndicatorModel.layout(direction: .right, progress: 1, travel: 50)
        #expect(layout == IndicatorLayout(opacity: 1, arrowOffset: 0, isArmed: true))
    }

    @Test func halfwayIsHalfOpaqueAndHalfTravelled() {
        let layout = IndicatorModel.layout(direction: .right, progress: 0.5, travel: 50)
        #expect(layout == IndicatorLayout(opacity: 0.5, arrowOffset: -25, isArmed: false))
    }

    @Test func leftMirrorsRight() {
        let left = IndicatorModel.layout(direction: .left, progress: 0.25, travel: 40)
        let right = IndicatorModel.layout(direction: .right, progress: 0.25, travel: 40)
        #expect(left.arrowOffset == -right.arrowOffset)
        #expect(left.arrowOffset > 0)
        #expect(left.opacity == right.opacity)
    }

    @Test func progressIsClamped() {
        #expect(IndicatorModel.layout(direction: .left, progress: 3, travel: 50).opacity == 1)
        #expect(IndicatorModel.layout(direction: .left, progress: -1, travel: 50).arrowOffset == 50)
    }
}
