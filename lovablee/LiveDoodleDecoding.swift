import Foundation

extension JSONDecoder {
    /// Supabase Realtime and RPC timestamps can be Postgres-style: "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX".
    static var liveDoodle: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)

            if let isoDate = ISO8601DateFormatter().date(from: raw) {
                return isoDate
            }

            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            if let parsed = formatter.date(from: raw) {
                return parsed
            }

            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unrecognized date format: \(raw)"
                )
            )
        }
        return decoder
    }
}

enum LiveDoodleParser {
    static func parse(json: [String: Any]) -> LiveDoodle? {
        guard
            let idString = json["id"] as? String,
            let id = UUID(uuidString: idString),
            let coupleKey = json["couple_key"] as? String ?? json["coupleKey"] as? String,
            let senderId = json["sender_id"] as? String ?? json["senderId"] as? String,
            let content = json["content_base64"] as? String ?? json["contentBase64"] as? String
        else { return nil }

        let senderName = json["sender_name"] as? String ?? json["senderName"] as? String
        let createdAt = parseDate(json["created_at"] as? String ?? json["createdAt"] as? String)

        return LiveDoodle(
            id: id,
            coupleKey: coupleKey,
            senderId: senderId,
            senderName: senderName,
            contentBase64: content,
            createdAt: createdAt ?? Date()
        )
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        if let iso = ISO8601DateFormatter().date(from: raw) { return iso }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"
        if let parsed = formatter.date(from: raw) { return parsed }

        formatter.dateFormat = "yyyy-MM-dd HH:mm:ssXXXXX"
        return formatter.date(from: raw)
    }
}
