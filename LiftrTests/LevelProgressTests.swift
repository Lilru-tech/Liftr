import Foundation
import Testing
@testable import Liftr

struct LevelProgressTests {
    @Test func levelOneBandUsesFloorZero() {
        let ratio = levelProgressRatio(totalXp: 60, currentLevelThresholdXp: 0, nextLevelThresholdXp: 120)
        #expect(ratio == 0.5)
    }

    @Test func higherLevelUsesWithinBandNotLifetimeOverNextCap() {
        let ratio = levelProgressRatio(totalXp: 11_700, currentLevelThresholdXp: 10_000, nextLevelThresholdXp: 13_000)
        #expect(abs(ratio - 0.5666666666666666) < 0.0001)
    }

    @Test func atCurrentFloorIsZeroPercent() {
        let ratio = levelProgressRatio(totalXp: 10_000, currentLevelThresholdXp: 10_000, nextLevelThresholdXp: 13_000)
        #expect(ratio == 0)
    }

    @Test func atNextCapIsOneHundredPercent() {
        let ratio = levelProgressRatio(totalXp: 13_000, currentLevelThresholdXp: 10_000, nextLevelThresholdXp: 13_000)
        #expect(ratio == 1)
    }

    @Test func invalidSpanReturnsZero() {
        let ratio = levelProgressRatio(totalXp: 500, currentLevelThresholdXp: 600, nextLevelThresholdXp: 600)
        #expect(ratio == 0)
    }

    @Test func clampsBelowFloorAndAboveCap() {
        #expect(levelProgressRatio(totalXp: 9_000, currentLevelThresholdXp: 10_000, nextLevelThresholdXp: 13_000) == 0)
        #expect(levelProgressRatio(totalXp: 15_000, currentLevelThresholdXp: 10_000, nextLevelThresholdXp: 13_000) == 1)
    }
}
