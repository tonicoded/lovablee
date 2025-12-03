//
//  WidgetSyncService.swift
//  lovablee
//
//  Service to sync widget data independent of UI state
//

import Foundation
import WidgetKit

final class WidgetSyncService {
    static let shared = WidgetSyncService()

    private init() {}

    /// Fetch the latest partner doodle and update widget
    @discardableResult
    func syncWidgetWithLatestDoodle() async -> Bool {
        print("🎨 WidgetSyncService: Starting widget sync...")

        guard var session = WidgetDataStore.shared.loadSession(allowExpired: true) else {
            print("❌ WidgetSyncService: No session available")
            return false
        }

        do {
            // Try fetching with current session
            let result = try await fetchDoodleWithSession(session)
            if result {
                return true
            }
            return false
        } catch {
            // If 401, try refreshing session once
            if let httpError = error as? URLError, httpError.code == .userAuthenticationRequired {
                print("🔄 WidgetSyncService: Session expired, attempting refresh...")

                guard let refreshedSession = try? await refreshSession(session) else {
                    print("❌ WidgetSyncService: Session refresh failed")
                    return false
                }

                session = refreshedSession

                // Retry with refreshed session
                if let result = try? await fetchDoodleWithSession(session) {
                    return result
                }
            }

            print("❌ WidgetSyncService: Error - \(error.localizedDescription)")
            return false
        }
    }

    private func fetchDoodleWithSession(_ session: WidgetSessionData) async throws -> Bool {
        let projectURL = URL(string: "https://ahtkqcaxeycxvwntjcxp.supabase.co")!
        let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFodGtxY2F4ZXljeHZ3bnRqY3hwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ1MDI3MDQsImV4cCI6MjA4MDA3ODcwNH0.cyIkcEN6wd71cis85jAOCMHrx8RoHbuMuUOvi_b10SI"

        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/get_doodles"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload = ["p_limit": 1]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        // Throw error on 401 so we can retry with refresh
        if httpResponse.statusCode == 401 {
            throw URLError(.userAuthenticationRequired)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ WidgetSyncService: API request failed with status \(httpResponse.statusCode)")
            return false
        }

        struct DoodleResponse: Codable {
            let senderId: String
            let senderName: String
            let content: String?

            enum CodingKeys: String, CodingKey {
                case senderId = "sender_id"
                case senderName = "sender_name"
                case content
            }
        }

        let doodles = try JSONDecoder().decode([DoodleResponse].self, from: data)

        guard let latestDoodle = doodles.first,
              latestDoodle.senderId != session.userId,
              let content = latestDoodle.content else {
            print("❌ WidgetSyncService: No partner doodle found")
            return false
        }

        // Decode base64 image
        var base64String = content
        if let comma = content.firstIndex(of: ",") {
            base64String = String(content[content.index(after: comma)...])
        }

        guard let imageData = Data(base64Encoded: base64String) else {
            print("❌ WidgetSyncService: Failed to decode doodle image")
            return false
        }

        // Save to widget data store
        WidgetDataStore.shared.saveLatestDoodle(
            imageData: imageData,
            partnerName: latestDoodle.senderName
        )

        print("✅ WidgetSyncService: Widget updated successfully with doodle from \(latestDoodle.senderName)")
        return true
    }

    private func refreshSession(_ oldSession: WidgetSessionData) async throws -> WidgetSessionData {
        print("🔄 WidgetSyncService: Refreshing session with token: \(oldSession.refreshToken.prefix(10))...")

        // Check if refresh token is valid
        guard !oldSession.refreshToken.isEmpty else {
            print("❌ WidgetSyncService: Refresh token is empty")
            throw URLError(.userAuthenticationRequired)
        }

        let projectURL = URL(string: "https://ahtkqcaxeycxvwntjcxp.supabase.co")!
        let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFodGtxY2F4ZXljeHZ3bnRqY3hwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ1MDI3MDQsImV4cCI6MjA4MDA3ODcwNH0.cyIkcEN6wd71cis85jAOCMHrx8RoHbuMuUOvi_b10SI"

        var components = URLComponents(url: projectURL.appendingPathComponent("auth/v1/token"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")

        let body = ["refresh_token": oldSession.refreshToken]
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ WidgetSyncService: No HTTP response from refresh endpoint")
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorBody = String(data: data, encoding: .utf8) {
                print("❌ WidgetSyncService: Refresh failed with status \(httpResponse.statusCode): \(errorBody)")
            } else {
                print("❌ WidgetSyncService: Refresh failed with status \(httpResponse.statusCode)")
            }
            throw URLError(.userAuthenticationRequired)
        }

        struct RefreshResponse: Codable {
            let accessToken: String
            let refreshToken: String
            let expiresIn: Int

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case refreshToken = "refresh_token"
                case expiresIn = "expires_in"
            }
        }

        let decoder = JSONDecoder()
        let refreshData = try decoder.decode(RefreshResponse.self, from: data)

        let expiresAt = Date().addingTimeInterval(TimeInterval(refreshData.expiresIn))
        let newSession = WidgetSessionData(
            accessToken: refreshData.accessToken,
            refreshToken: refreshData.refreshToken,
            userId: oldSession.userId,
            expiresAt: expiresAt
        )

        // Save updated session
        WidgetDataStore.shared.saveSession(
            accessToken: newSession.accessToken,
            refreshToken: newSession.refreshToken,
            userId: newSession.userId,
            expiresAt: newSession.expiresAt
        )

        print("✅ WidgetSyncService: Session refreshed successfully")
        return newSession
    }
}
