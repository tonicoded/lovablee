import Foundation

struct SupabasePetStatus: Codable {
    let userId: String
    let petName: String
    let mood: String
    let hydrationLevel: Int
    let playfulnessLevel: Int
    let hearts: Int
    let streakCount: Int
    let lastActiveDate: Date?
    let lastWateredAt: Date?
    let lastPlayedAt: Date?
    let adoptedAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case userId
        case petName
        case mood
        case hydrationLevel
        case playfulnessLevel
        case hearts
        case streakCount
        case lastActiveDate
        case lastWateredAt
        case lastPlayedAt
        case adoptedAt
        case updatedAt
    }

    init(userId: String,
         petName: String,
         mood: String,
         hydrationLevel: Int,
         playfulnessLevel: Int,
         hearts: Int = 0,
         streakCount: Int = 0,
         lastActiveDate: Date? = nil,
         lastWateredAt: Date?,
         lastPlayedAt: Date?,
         adoptedAt: Date?,
         updatedAt: Date?) {
        self.userId = userId
        self.petName = petName
        self.mood = mood
        self.hydrationLevel = hydrationLevel
        self.playfulnessLevel = playfulnessLevel
        self.hearts = hearts
        self.streakCount = streakCount
        self.lastActiveDate = lastActiveDate
        self.lastWateredAt = lastWateredAt
        self.lastPlayedAt = lastPlayedAt
        self.adoptedAt = adoptedAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        petName = try container.decode(String.self, forKey: .petName)
        mood = try container.decode(String.self, forKey: .mood)
        hydrationLevel = try container.decode(Int.self, forKey: .hydrationLevel)
        playfulnessLevel = try container.decode(Int.self, forKey: .playfulnessLevel)
        hearts = try container.decodeIfPresent(Int.self, forKey: .hearts) ?? 0
        streakCount = try container.decodeIfPresent(Int.self, forKey: .streakCount) ?? 0
        if let dateString = try container.decodeIfPresent(String.self, forKey: .lastActiveDate) {
            lastActiveDate = ISO8601DateFormatter().date(from: dateString)
        } else {
            lastActiveDate = try container.decodeIfPresent(Date.self, forKey: .lastActiveDate)
        }
        lastWateredAt = try container.decodeIfPresent(Date.self, forKey: .lastWateredAt)
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        adoptedAt = try container.decodeIfPresent(Date.self, forKey: .adoptedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

enum PetActionType: String, Codable {
    case water
    case play
}

struct LoveNote: Codable, Identifiable {
    let id: UUID
    let coupleKey: String
    let senderId: String
    let senderName: String
    let message: String
    let isRead: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case coupleKey
        case senderId
        case senderName
        case message
        case isRead
        case createdAt
    }
}

struct SupabaseActivityItem: Codable, Identifiable {
    let id: UUID
    let coupleKey: String?
    let actorId: String
    let actorName: String?
    let actionType: String
    let petName: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case coupleKey
        case actorId
        case actorName
        case actionType
        case petName
        case createdAt
    }
}

#if DEBUG
extension SupabasePetStatus {
    static var preview: SupabasePetStatus {
        SupabasePetStatus(
            userId: UUID().uuidString,
            petName: "Bubba",
            mood: "Joyful",
            hydrationLevel: 88,
            playfulnessLevel: 72,
            hearts: 80,
            streakCount: 5,
            lastActiveDate: Date().addingTimeInterval(-60 * 60 * 2),
            lastWateredAt: Date().addingTimeInterval(-60 * 60 * 7),
            lastPlayedAt: Date().addingTimeInterval(-60 * 60 * 3),
            adoptedAt: Date().addingTimeInterval(-60 * 60 * 24 * 12),
            updatedAt: Date().addingTimeInterval(-60 * 5)
        )
    }

    static var cooldownPreview: SupabasePetStatus {
        SupabasePetStatus(
            userId: UUID().uuidString,
            petName: "Bubba",
            mood: "Sleepy",
            hydrationLevel: 64,
            playfulnessLevel: 38,
            hearts: 12,
            streakCount: 2,
            lastActiveDate: Date().addingTimeInterval(-60 * 60 * 2),
            lastWateredAt: Date().addingTimeInterval(-60 * 60 * 2),
            lastPlayedAt: Date().addingTimeInterval(-60 * 15),
            adoptedAt: Date().addingTimeInterval(-60 * 60 * 24 * 3),
            updatedAt: Date().addingTimeInterval(-60 * 20)
        )
    }
}
#endif
