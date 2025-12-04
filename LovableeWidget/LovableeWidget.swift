//
//  LovableeWidget.swift
//  LovableeWidget
//
//  Created by Anthony Verruijt on 02/12/2025.
//

import WidgetKit
import SwiftUI

struct LovableeWidget: Widget {
    let kind: String = "LovableeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DoodleTimelineProvider()) { entry in
            DoodleWidgetView(entry: entry)
                .environment(\.colorScheme, .light)
        }
        .configurationDisplayName("Partner's Doodle")
        .description("See the latest doodle from your partner")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DoodleWidgetView: View {
    var entry: DoodleEntry
    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        if let imageData = entry.doodleImageData,
           let uiImage = UIImage(data: imageData) {
            // Doodle fills entire widget edge-to-edge
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("from \(entry.partnerName)")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.7), radius: 3, x: 0, y: 1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial.opacity(0.9))
                        )
                    Spacer()
                }
            }
            .padding(.horizontal, widgetFamily == .systemSmall ? 8 : 12)
            .padding(.bottom, widgetFamily == .systemSmall ? 8 : 12)
            .containerBackground(for: .widget) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            // Empty state
            ZStack {
                VStack(spacing: 8) {
                    Image(systemName: "paintbrush.fill")
                        .font(.system(size: 40))
                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.5).opacity(0.3))

                    Text("No doodles yet")
                        .font(.caption)
                        .foregroundColor(Color(red: 0.4, green: 0.3, blue: 0.5).opacity(0.6))
                }
            }
            .containerBackground(for: .widget) {
                LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 0.97, blue: 0.95),
                        Color(red: 0.98, green: 0.95, blue: 0.93)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

struct DoodleEntry: TimelineEntry {
    let date: Date
    let doodleImageData: Data?
    let partnerName: String
}

struct DoodleTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoodleEntry {
        DoodleEntry(date: Date(), doodleImageData: nil, partnerName: "Partner")
    }

    func getSnapshot(in context: Context, completion: @escaping (DoodleEntry) -> Void) {
        let entry = DoodleEntry(date: Date(), doodleImageData: nil, partnerName: "Partner")
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DoodleEntry>) -> Void) {
        Task {
            let entry = await fetchLatestDoodle()
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
            let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
            completion(timeline)
        }
    }

    private func fetchLatestDoodle() async -> DoodleEntry {
        print("🔍 Widget: Attempting to load cached doodle...")
        // Try to load from shared storage first (for quick display)
        if let cachedData = WidgetDataStore.shared.loadLatestDoodle() {
            print("✅ Widget: Found cached doodle from \(cachedData.partnerName), size: \(cachedData.imageData.count) bytes")
            if UIImage(data: cachedData.imageData) != nil {
                print("✅ Widget: Image data is valid")
            } else {
                print("❌ Widget: Image data is corrupted!")
            }
            return DoodleEntry(
                date: Date(),
                doodleImageData: cachedData.imageData,
                partnerName: cachedData.partnerName
            )
        }
        print("❌ Widget: No cached doodle found")

        // If no cached data, try to fetch from server
        do {
            if let session = WidgetDataStore.shared.loadSession(),
               let (imageData, partnerName) = try await fetchDoodleFromServer(session: session) {

                // Cache the fetched data
                WidgetDataStore.shared.saveLatestDoodle(imageData: imageData, partnerName: partnerName)

                return DoodleEntry(
                    date: Date(),
                    doodleImageData: imageData,
                    partnerName: partnerName
                )
            }
        } catch {
            print("Widget: Failed to fetch doodle: \(error)")
        }

        return DoodleEntry(date: Date(), doodleImageData: nil, partnerName: "Partner")
    }

    private func fetchDoodleFromServer(session: WidgetSessionData) async throws -> (Data, String)? {
        let projectURL = URL(string: "https://ahtkqcaxeycxvwntjcxp.supabase.co")!
        let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFodGtxY2F4ZXljeHZ3bnRqY3hwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ1MDI3MDQsImV4cCI6MjA4MDA3ODcwNH0.P0xgzBylvJ8CU_0-jKxOb-rFZm1gjdO_ib1hVB9FVpA"

        // Fetch latest doodle metadata
        var request = URLRequest(url: projectURL.appendingPathComponent("rest/v1/rpc/get_doodles"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        let payload = ["p_limit": 1]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw WidgetError.networkError
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        let doodles = try decoder.decode([WidgetDoodle].self, from: data)

        guard let latestDoodle = doodles.first,
              latestDoodle.senderId != session.userId else {
            return nil // No partner doodles
        }

        // Try to decode from base64 content first
        if let content = latestDoodle.content {
            var payload = content
            // Remove data:image/png;base64, prefix if present
            if let comma = content.firstIndex(of: ",") {
                payload = String(content[content.index(after: comma)...])
            }

            guard let imageData = Data(base64Encoded: payload) else {
                throw WidgetError.noData
            }
            return (imageData, latestDoodle.senderName)
        }

        // Fallback to storage path (for old doodles)
        if let storagePath = latestDoodle.storagePath {
            let imageURL = URL(string: "https://ahtkqcaxeycxvwntjcxp.supabase.co/storage/v1/object/public/storage/\(storagePath)")!
            let (imageData, _) = try await URLSession.shared.data(from: imageURL)
            return (imageData, latestDoodle.senderName)
        }

        throw WidgetError.noData
    }
}

struct WidgetDoodle: Codable {
    let id: UUID
    let senderId: String
    let senderName: String
    let storagePath: String?
    let content: String?
    let createdAt: Date
}

enum WidgetError: Error {
    case networkError
    case noData
}

#Preview(as: .systemSmall) {
    LovableeWidget()
} timeline: {
    DoodleEntry(date: .now, doodleImageData: nil, partnerName: "Partner")
}
