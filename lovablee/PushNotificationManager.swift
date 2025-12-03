import Combine
import Foundation
import UIKit
import UserNotifications
import WidgetKit

final class PushNotificationManager: NSObject, ObservableObject {
    @Published private(set) var deviceToken: String?
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    func beginRegistrationFlow() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            self?.setAuthorizationStatus(settings.authorizationStatus)
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    if let error = error {
                        NSLog("Push authorization error: \(error.localizedDescription)")
                        return
                    }
                    guard granted else {
                        self?.refreshAuthorizationStatus()
                        return
                    }
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                    self?.refreshAuthorizationStatus()
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            case .denied:
                NSLog("Push notifications denied by user.")
            @unknown default:
                break
            }
        }
    }

    func updateDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        DispatchQueue.main.async {
            if self.deviceToken != token {
                self.deviceToken = token
            }
        }
    }

    func handleRegistrationError(_ error: Error) {
        NSLog("APNs registration failed: \(error.localizedDescription)")
    }

    private func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            self?.setAuthorizationStatus(settings.authorizationStatus)
        }
    }

    private func setAuthorizationStatus(_ status: UNAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var pushManager: PushNotificationManager?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pushManager?.updateDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        pushManager?.handleRegistrationError(error)
    }

    // Handle remote notification when app is in background or foreground
    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        print("📱 Received remote notification: \(userInfo)")

        // Check if this is a doodle notification
        if let notificationType = userInfo["type"] as? String, notificationType == "doodle" {
            print("🎨 New doodle notification received - triggering widget update")

            // Sync widget with latest doodle
            guard WidgetDataStore.shared.hasStoredSession else {
                completionHandler(.noData)
                return
            }
            Task {
                let success = await WidgetSyncService.shared.syncWidgetWithLatestDoodle()
                completionHandler(success ? .newData : .noData)
            }
        } else {
            // Reload widget anyway to be safe
            WidgetCenter.shared.reloadAllTimelines()
            completionHandler(.noData)
        }
    }

    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("📱 Notification will present (foreground)")

        guard WidgetDataStore.shared.hasStoredSession else { return }
        // Sync widget when notification arrives in foreground
        Task {
            await WidgetSyncService.shared.syncWidgetWithLatestDoodle()
        }

        // Show banner and play sound even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        print("📱 User tapped notification")

        guard WidgetDataStore.shared.hasStoredSession else {
            completionHandler()
            return
        }
        // Sync widget when user taps notification
        Task {
            await WidgetSyncService.shared.syncWidgetWithLatestDoodle()
        }

        completionHandler()
    }

}
