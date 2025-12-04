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
    let lastFedAt: Date?
    let lastNoteSentAt: Date?
    let lastDoodleCreatedAt: Date?
    let lastPlantWateredAt: Date?
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
        case lastFedAt
        case lastNoteSentAt
        case lastDoodleCreatedAt
        case lastPlantWateredAt
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
         lastFedAt: Date? = nil,
         lastNoteSentAt: Date? = nil,
         lastDoodleCreatedAt: Date? = nil,
         lastPlantWateredAt: Date? = nil,
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
        self.lastFedAt = lastFedAt
        self.lastNoteSentAt = lastNoteSentAt
        self.lastDoodleCreatedAt = lastDoodleCreatedAt
        self.lastPlantWateredAt = lastPlantWateredAt
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
        lastFedAt = try container.decodeIfPresent(Date.self, forKey: .lastFedAt)
        lastNoteSentAt = try container.decodeIfPresent(Date.self, forKey: .lastNoteSentAt)
        lastDoodleCreatedAt = try container.decodeIfPresent(Date.self, forKey: .lastDoodleCreatedAt)
        lastPlantWateredAt = try container.decodeIfPresent(Date.self, forKey: .lastPlantWateredAt)
        adoptedAt = try container.decodeIfPresent(Date.self, forKey: .adoptedAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

enum PetActionType: String, Codable {
    case water
    case play
    case feed
    case note
    case doodle
    case plant
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

struct Doodle: Codable, Identifiable {
    let id: UUID
    let coupleKey: String
    let senderId: String
    let senderName: String
    let storagePath: String?
    let content: String?
    let isViewed: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case coupleKey
        case senderId
        case senderName
        case storagePath
        case content
        case isViewed
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

// MARK: - Mood Models

struct MoodEntry: Codable, Identifiable {
    let id: UUID
    let userId: String
    let moodKey: String
    let emoji: String?
    let label: String?
    let moodDate: Date
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case moodKey = "mood_key"
        case emoji
        case label
        case moodDate = "mood_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(id: UUID,
         userId: String,
         moodKey: String,
         emoji: String?,
         label: String?,
         moodDate: Date,
         createdAt: Date? = nil,
         updatedAt: Date? = nil) {
        self.id = id
        self.userId = userId
        self.moodKey = moodKey
        self.emoji = emoji
        self.label = label
        self.moodDate = moodDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(String.self, forKey: .userId)
        moodKey = try container.decode(String.self, forKey: .moodKey)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        label = try container.decodeIfPresent(String.self, forKey: .label)

        let dateString = try container.decode(String.self, forKey: .moodDate)
        if let dateOnly = DateFormatter.yearMonthDay.date(from: dateString) {
            moodDate = dateOnly
        } else if let iso = ISO8601DateFormatter().date(from: dateString) {
            moodDate = iso
        } else {
            throw DecodingError.dataCorruptedError(forKey: .moodDate,
                                                   in: container,
                                                   debugDescription: "Invalid date format for mood_date")
        }

        let createdString = try container.decodeIfPresent(String.self, forKey: .createdAt)
        if let raw = createdString, let parsed = ISO8601DateFormatter().date(from: raw) {
            createdAt = parsed
        } else {
            createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        }

        let updatedString = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        if let raw = updatedString, let parsed = ISO8601DateFormatter().date(from: raw) {
            updatedAt = parsed
        } else {
            updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        }
    }
}

struct MoodPair: Codable {
    let myMood: MoodEntry?
    let partnerMood: MoodEntry?

    enum CodingKeys: String, CodingKey {
        case myMood = "my_mood"
        case partnerMood = "partner_mood"
    }
}

struct MoodOption: Identifiable {
    let id = UUID()
    let key: String
    let title: String
    let emoji: String

    static let defaults: [MoodOption] = [
        MoodOption(key: "relaxed", title: "Relaxed", emoji: "😌"),
        MoodOption(key: "calm", title: "Calm", emoji: "😊"),
        MoodOption(key: "amazing", title: "Amazing", emoji: "🤩"),
        MoodOption(key: "happy", title: "Happy", emoji: "😃"),
        MoodOption(key: "joyful", title: "Joyful", emoji: "😄"),
        MoodOption(key: "excited", title: "Excited", emoji: "😁"),
        MoodOption(key: "energetic", title: "Energetic", emoji: "⚡️"),
        MoodOption(key: "playful", title: "Playful", emoji: "😜"),
        MoodOption(key: "silly", title: "Silly", emoji: "🤪"),
        MoodOption(key: "focused", title: "Focused", emoji: "🧐"),
        MoodOption(key: "motivated", title: "Motivated", emoji: "💪"),
        MoodOption(key: "confident", title: "Confident", emoji: "😎"),
        MoodOption(key: "creative", title: "Creative", emoji: "🎨"),
        MoodOption(key: "hopeful", title: "Hopeful", emoji: "🙏"),
        MoodOption(key: "grateful", title: "Grateful", emoji: "🥰"),
        MoodOption(key: "content", title: "Content", emoji: "😌"),
        MoodOption(key: "mindful", title: "Mindful", emoji: "🧘"),
        MoodOption(key: "peaceful", title: "Peaceful", emoji: "🕊️"),
        MoodOption(key: "romantic", title: "Romantic", emoji: "💕"),
        MoodOption(key: "flirty", title: "Flirty", emoji: "😉"),
        MoodOption(key: "loving", title: "Loving", emoji: "❤️"),
        MoodOption(key: "smitten", title: "Smitten", emoji: "😍"),
        MoodOption(key: "sleepy", title: "Sleepy", emoji: "😴"),
        MoodOption(key: "proud", title: "Proud", emoji: "🥳"),
        MoodOption(key: "curious", title: "Curious", emoji: "🤔"),
        MoodOption(key: "cozy", title: "Cozy", emoji: "☕️")
    ]
}

extension DateFormatter {
    static let yearMonthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
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
            lastPlantWateredAt: Date().addingTimeInterval(-60 * 60 * 5),
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
            lastPlantWateredAt: Date().addingTimeInterval(-60 * 10),
            adoptedAt: Date().addingTimeInterval(-60 * 60 * 24 * 3),
            updatedAt: Date().addingTimeInterval(-60 * 20)
        )
    }
}
#endif
