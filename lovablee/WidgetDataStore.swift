import Foundation
import WidgetKit
import UIKit

struct WidgetSessionData: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let expiresAt: Date
}

struct WidgetDoodleData: Codable {
    let imageData: Data
    let partnerName: String
    let timestamp: Date
}

class WidgetDataStore {
    static let shared = WidgetDataStore()

    private let appGroupIdentifier = "group.com.anthony.lovablee"
    private let sessionKey = "widget_session_data"
    private let doodleKey = "widget_latest_doodle"
    private let sessionExistsKey = "lovablee.widget.session.exists"

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Session Management

    func saveSession(accessToken: String, refreshToken: String, userId: String, expiresAt: Date) {
        let sessionData = WidgetSessionData(
            accessToken: accessToken,
            refreshToken: refreshToken,
            userId: userId,
            expiresAt: expiresAt
        )

        guard let defaults = sharedDefaults else {
            WidgetCenter.shared.reloadAllTimelines()
            return
        }

        if let encoded = try? JSONEncoder().encode(sessionData) {
            defaults.set(encoded, forKey: sessionKey)
            defaults.synchronize() // Force immediate persistence
            UserDefaults.standard.set(true, forKey: sessionExistsKey)
            UserDefaults.standard.synchronize() // Force immediate persistence
            print("💾 Widget session saved and synchronized (userId: \(userId.prefix(8))..., refreshToken: \(refreshToken.prefix(10))...)")
        }

        // Reload all widget timelines after saving session
        WidgetCenter.shared.reloadAllTimelines()
    }

    func loadSession(allowExpired: Bool = false) -> WidgetSessionData? {
        guard let data = sharedDefaults?.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(WidgetSessionData.self, from: data) else {
            print("📭 No widget session found in storage")
            return nil
        }

        let isExpired = session.expiresAt < Date()
        print("📂 Loaded widget session: userId=\(session.userId.prefix(8))..., refreshToken=\(session.refreshToken.prefix(10))..., expired=\(isExpired)")

        if !allowExpired, isExpired {
            print("⏰ Session expired and allowExpired=false, returning nil")
            return nil
        }

        return session
    }

    var hasStoredSession: Bool {
        UserDefaults.standard.bool(forKey: sessionExistsKey)
    }

    func clearSession() {
        sharedDefaults?.removeObject(forKey: sessionKey)
        sharedDefaults?.synchronize() // Force immediate persistence
        UserDefaults.standard.set(false, forKey: sessionExistsKey)
        UserDefaults.standard.synchronize() // Force immediate persistence
        print("🧹 Widget session cleared and synchronized")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Doodle Data Management

    private func resizeImageForWidget(_ imageData: Data) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }

        // Widget max area is ~822935 pixels. Use 500x500 (250000 pixels) for small widgets
        let maxDimension: CGFloat = 500
        let size = image.size

        // If image is already small enough, return as-is
        if size.width <= maxDimension && size.height <= maxDimension {
            return imageData
        }

        // Calculate new size maintaining aspect ratio
        let aspectRatio = size.width / size.height
        var newSize: CGSize

        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }

        // Resize image
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return resizedImage?.pngData()
    }

    func saveLatestDoodle(imageData: Data, partnerName: String) {
        // Resize image to fit widget limits
        guard let resizedImageData = resizeImageForWidget(imageData) else {
            print("⚠️ Failed to resize image for widget")
            return
        }

        let doodleData = WidgetDoodleData(
            imageData: resizedImageData,
            partnerName: partnerName,
            timestamp: Date()
        )

        if let encoded = try? JSONEncoder().encode(doodleData) {
            sharedDefaults?.set(encoded, forKey: doodleKey)
            print("✅ Saved doodle for widget (resized to \(resizedImageData.count) bytes)")
        }

        // Reload all widget timelines after saving doodle
        WidgetCenter.shared.reloadAllTimelines()
    }

    func loadLatestDoodle() -> WidgetDoodleData? {
        guard let data = sharedDefaults?.data(forKey: doodleKey),
              let doodleData = try? JSONDecoder().decode(WidgetDoodleData.self, from: data) else {
            return nil
        }

        return doodleData
    }

    func clearDoodleData() {
        sharedDefaults?.removeObject(forKey: doodleKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
