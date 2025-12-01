import Combine
import Foundation
import UIKit
import UserNotifications

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
}
