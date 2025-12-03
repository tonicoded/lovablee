import Foundation

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

    func saveLatestDoodle(imageData: Data, partnerName: String) {
        let doodleData = WidgetDoodleData(
            imageData: imageData,
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
