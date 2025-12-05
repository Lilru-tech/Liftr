import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import Supabase
import GoogleMobileAds

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {

        FirebaseApp.configure()
        configurePushNotifications(application: application)
        MobileAds.shared.start(completionHandler: nil)

        if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            print("🚀 [AppDelegate] launched from push, userInfo:", remoteNotification)
            
            let userInfo = remoteNotification
            
            let notificationId: Int?
            if let idInt = userInfo["notification_id"] as? Int {
                notificationId = idInt
            } else if let idStr = userInfo["notification_id"] as? String,
                      let idParsed = Int(idStr) {
                notificationId = idParsed
            } else {
                notificationId = nil
            }
            
            var type = userInfo["type"] as? String ?? ""
            if type.isEmpty, let t = userInfo["notification_type"] as? String {
                type = t
            }
            print("🚀 [AppDelegate] launch parsed type:", type)
            
            var data: [String: Any] = [:]
            if let d = userInfo["data"] as? [String: Any] {
                data = d
            } else if let d = userInfo["data"] as? [String: String] {
                data = d
            } else if let jsonString = userInfo["data"] as? String {
                if let jsonData = jsonString.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                    data = obj
                }
            }
            
            if data.isEmpty {
                if let followerId = userInfo["follower_id"] as? String {
                    data["follower_id"] = followerId
                }
                if let workoutId = userInfo["workout_id"] as? String {
                    data["workout_id"] = workoutId
                }
                if let ownerId = userInfo["owner_id"] as? String {
                    data["owner_id"] = ownerId
                }
            }
            
            print("🚀 [AppDelegate] launch parsed data:", data)
            
            Task { @MainActor in
                print("🚀 [AppDelegate] setting pendingNotification from launchOptions")
                AppState.shared.handlePushNotificationTap(
                    notificationId: notificationId,
                    type: type,
                    data: data
                )
            }
        }

        return true
    }

    private func configurePushNotifications(application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("❌ Error pidiendo permisos de notificación:", error)
                return
            }

            print("🔔 Permisos de notificación concedidos:", granted)

            guard granted else { return }

            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }

        Messaging.messaging().delegate = self
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ Error al registrar APNs:", error)
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        print("📲 FCM registration token:", fcmToken ?? "nil")

        guard let token = fcmToken, !token.isEmpty else { return }

        Task {
            await NotificationTokenUploader.shared.updateFcmToken(token)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {

        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("🔔 [AppDelegate] didReceive userInfo:", userInfo)
        
        let notificationId: Int?
        if let idInt = userInfo["notification_id"] as? Int {
            notificationId = idInt
        } else if let idStr = userInfo["notification_id"] as? String,
                  let idParsed = Int(idStr) {
            notificationId = idParsed
        } else {
            notificationId = nil
        }
        
        var type = userInfo["type"] as? String ?? ""
        if type.isEmpty, let t = userInfo["notification_type"] as? String {
            type = t
        }
        print("🔔 [AppDelegate] parsed type:", type)
        
        var data: [String: Any] = [:]
        if let d = userInfo["data"] as? [String: Any] {
            data = d
        } else if let d = userInfo["data"] as? [String: String] {
            data = d
        } else if let jsonString = userInfo["data"] as? String {
            if let jsonData = jsonString.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                data = obj
            }
        }
        
        if data.isEmpty {
            if let followerId = userInfo["follower_id"] as? String {
                data["follower_id"] = followerId
            }
            if let workoutId = userInfo["workout_id"] as? String {
                data["workout_id"] = workoutId
            }
            if let ownerId = userInfo["owner_id"] as? String {
                data["owner_id"] = ownerId
            }
        }
        
        print("🔔 [AppDelegate] parsed data:", data)
        
        Task { @MainActor in
            print("🔔 [AppDelegate] calling handlePushNotificationTap")
            AppState.shared.handlePushNotificationTap(
                notificationId: notificationId,
                type: type,
                data: data
            )
        }
        
        completionHandler()
    }
}
