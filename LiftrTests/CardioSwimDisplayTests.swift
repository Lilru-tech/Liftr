import Foundation
import Testing
@testable import Liftr

struct CardioSwimDisplayTests {

    @Test func screenshotExample_pacePer100m() {
        let durationSec = 49 * 60 + 12
        let meters = 2225
        let pace = CardioSwimDisplay.autoPaceSecPerKm(
            distanceMetersText: "\(meters)",
            durationSec: durationSec
        )
        #expect(pace != nil)
        let secPerKm = pace!
        #expect(secPerKm >= 1320 && secPerKm <= 1335)
        let label = CardioSwimDisplay.formatSwimPace(secPerKm: secPerKm)
        #expect(label == "2:13 /100m")
    }

    @Test func metersKmRoundTrip() {
        let km = CardioSwimDisplay.distanceKm(fromMetersText: "2225")
        #expect(km != nil)
        #expect(abs(km! - 2.225) < 0.0001)
        #expect(CardioSwimDisplay.metersText(fromKm: km) == "2225")
    }

    @Test func poolLapsTimesLength() {
        #expect(CardioSwimDisplay.poolDistanceMeters(lapsText: "25", poolLengthMText: "25") == 625)
    }

    @Test func isSwimActivity_aliases() {
        #expect(CardioSwimDisplay.isSwimActivity(code: "swim_pool"))
        #expect(CardioSwimDisplay.isSwimActivity(code: "swim_open_water"))
        #expect(CardioSwimDisplay.isSwimActivity(code: "pool_swim"))
        #expect(!CardioSwimDisplay.isSwimActivity(code: "run"))
    }
}
