import Foundation
import Testing
@testable import Liftr

@Suite(.serialized)
struct HealthKitCardioSyncRegressionTests {
    @Test func syncEnabledDefaultsFalseWhenKeyMissing() {
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
        #expect(HealthKitCardioSyncService.shared.isSyncEnabled == false)
    }

    @Test func syncEnabledPersistsExplicitPreference() {
        let key = "cardioHealthSyncEnabled"
        let defaults = UserDefaults.standard
        let hadValue = defaults.object(forKey: key) != nil
        let previous = hadValue ? defaults.bool(forKey: key) : nil
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        HealthKitCardioSyncService.shared.isSyncEnabled = true
        #expect(HealthKitCardioSyncService.shared.isSyncEnabled == true)
        HealthKitCardioSyncService.shared.isSyncEnabled = false
        #expect(HealthKitCardioSyncService.shared.isSyncEnabled == false)
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
