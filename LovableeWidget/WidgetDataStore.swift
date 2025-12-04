import Foundation
import UIKit

struct WidgetSessionData: Codable {
    let accessToken: String
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

    private var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }

    // MARK: - Session Management

    func saveSession(accessToken: String, userId: String, expiresAt: Date) {
        let sessionData = WidgetSessionData(
            accessToken: accessToken,
            userId: userId,
            expiresAt: expiresAt
        )

        if let encoded = try? JSONEncoder().encode(sessionData) {
            sharedDefaults?.set(encoded, forKey: sessionKey)
        }
    }

    func loadSession() -> WidgetSessionData? {
        guard let data = sharedDefaults?.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(WidgetSessionData.self, from: data) else {
            return nil
        }

        // Check if session is expired
        if session.expiresAt < Date() {
            return nil
        }

        return session
    }

    func clearSession() {
        sharedDefaults?.removeObject(forKey: sessionKey)
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
            print("Widget: Failed to resize image")
            return
        }

        let doodleData = WidgetDoodleData(
            imageData: resizedImageData,
            partnerName: partnerName,
            timestamp: Date()
        )

        if let encoded = try? JSONEncoder().encode(doodleData) {
            sharedDefaults?.set(encoded, forKey: doodleKey)
        }
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
    }
}
