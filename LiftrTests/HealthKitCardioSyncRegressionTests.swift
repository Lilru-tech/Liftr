import Foundation
import Testing
@testable import Liftr

struct HealthKitCardioSyncRegressionTests {
    @Test func syncEnabledDefaultsTrueWhenKeyMissing() {
        let key = "cardioHealthSyncEnabled"
        let defaults = UserDefaults.standard
        let hadValue = defaults.object(forKey: key) != nil
        let previous = hadValue ? defaults.bool(forKey: key) : nil
        defaults.removeObject(forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        #expect(HealthKitCardioSyncService.shared.isSyncEnabled == true)
    }

    @Test func shouldNotifyOnlyForRecentAutoImports() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let recent = now.addingTimeInterval(-3600)
        let old = now.addingTimeInterval(-(49 * 3600))
        #expect(HealthKitCardioImportNotificationPolicy.shouldNotifyAutoImport(workoutEndedAt: recent, now: now))
        #expect(!HealthKitCardioImportNotificationPolicy.shouldNotifyAutoImport(workoutEndedAt: old, now: now))
    }

    @Test func shouldNotifyAtExactly48Hours() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let boundary = now.addingTimeInterval(-HealthKitCardioImportNotificationPolicy.recentImportWindow)
        #expect(HealthKitCardioImportNotificationPolicy.shouldNotifyAutoImport(workoutEndedAt: boundary, now: now))
    }
}
