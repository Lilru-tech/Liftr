import Foundation
import Testing
@testable import Liftr

struct StrengthRestPresetRegressionTests {
    @Test func fallsBackWhenFewerThanFiveRests() {
        let rests = [90, 90, 90, 90]
        #expect(StrengthRestPresetService.computePresets(restSeconds: rests) == StrengthRestPresetService.defaultPresets)
    }

    @Test func usesTopFiveMostFrequentSortedAscending() {
        var rests: [Int] = Array(repeating: 80, count: 12)
        rests += Array(repeating: 100, count: 9)
        rests += Array(repeating: 120, count: 8)
        rests += Array(repeating: 90, count: 2)
        rests += Array(repeating: 60, count: 1)
        #expect(StrengthRestPresetService.computePresets(restSeconds: rests) == [60, 80, 90, 100, 120])
    }

    @Test func tieBreakPrefersHigherRestSec() {
        var rests: [Int] = []
        rests += Array(repeating: 50, count: 2)
        rests += Array(repeating: 60, count: 2)
        rests += Array(repeating: 70, count: 2)
        rests += Array(repeating: 80, count: 2)
        rests += Array(repeating: 90, count: 2)
        rests += Array(repeating: 100, count: 2)
        #expect(StrengthRestPresetService.computePresets(restSeconds: rests) == [60, 70, 80, 90, 100])
    }

    @Test func padsWithDefaultsWhenFewerThanFiveDistinctValues() {
        let rests = Array(repeating: 90, count: 6) + Array(repeating: 120, count: 4)
        #expect(StrengthRestPresetService.computePresets(restSeconds: rests) == [30, 60, 90, 120, 180])
    }

    @Test func ignoresZeroNullAndExtremeRestValues() {
        let rests = [0, 0, 90, 90, 90, 90, 90, 700, 700]
        #expect(StrengthRestPresetService.computePresets(restSeconds: rests) == StrengthRestPresetService.defaultPresets)
    }
}
