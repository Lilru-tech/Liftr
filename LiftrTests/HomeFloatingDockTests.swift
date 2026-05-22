import Testing
@testable import Liftr

struct HomeFloatingDockTests {

    @Test func shouldMerge_whenWithinThreshold() {
        let a = CGPoint(x: 360, y: 500)
        let b = CGPoint(x: 380, y: 510)
        #expect(HomeFloatingDock.shouldMerge(a, b))
    }

    @Test func shouldNotMerge_whenFarApart() {
        let a = CGPoint(x: 360, y: 500)
        let b = CGPoint(x: 360, y: 200)
        #expect(!HomeFloatingDock.shouldMerge(a, b))
    }

    @Test func unmergeOffsetsAlongSameEdge() {
        let result = HomeFloatingDock.unmergePositions(edge: .right, mergedPosition: 0.5)
        #expect(result.chat.0 == .right)
        #expect(result.quick.0 == .right)
        #expect(abs(result.chat.1 - 0.42) < 0.001)
        #expect(abs(result.quick.1 - 0.58) < 0.001)
    }
}
