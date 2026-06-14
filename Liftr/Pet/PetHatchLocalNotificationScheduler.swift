import Foundation
import UserNotifications

enum PetHatchLocalNotificationScheduler {
    static func schedule(hatchAt: Date, petType: String) {
        let interval = hatchAt.timeIntervalSinceNow
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your egg is ready to hatch!"
        content.body = "Your \(petType.replacingOccurrences(of: "_", with: " ")) egg is ready to hatch!"
        content.sound = .default
        content.userInfo = [
            "type": "pet_hatched",
            "source": "local_hatch_alarm"
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: PetHatchEventHandler.localNotificationIdentifier,
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            UNUserNotificationCenter.current().add(request)
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [PetHatchEventHandler.localNotificationIdentifier])
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [PetHatchEventHandler.localNotificationIdentifier])
    }
}
