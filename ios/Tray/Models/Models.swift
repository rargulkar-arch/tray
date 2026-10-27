import Foundation

// Every type here mirrors one function in supabase/migrations. Snake case from
// Postgres is converted automatically, so `display_name` arrives as displayName.

struct Me: Codable, Equatable {
    let id: String
    var username: String
    var displayName: String
    var emoji: String
    var phone: String?
    var campusSlug: String?
    var invisibleUntil: Date?

    /// Hidden right now — friends cannot see where you are eating.
    var isInvisible: Bool {
        guard let until = invisibleUntil else { return false }
        return until > Date()
    }
}

struct DiningHall: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let building: String?
    let lat: Double
    let lng: Double
    let radiusM: Double
    let sortOrder: Int
    let active: Bool
}

/// Where a friend is, and since when. The entire payload of the app.
struct Presence: Codable, Identifiable, Equatable {
    let userId: String
    let displayName: String
    let username: String
    let emoji: String
    let hallId: String
    let hallName: String
    let startedAt: Date
    let notifyOn: Bool
    let labelIds: [String]

    var id: String { userId }
}

struct MyCheckIn: Codable, Identifiable, Equatable {
    let id: String
    let hallId: String
    let hallName: String
    let startedAt: Date
    let source: String

    /// True when you tapped a hall yourself instead of walking into one.
    var wasManual: Bool { source == "manual" }
}

struct HallBusyness: Codable, Equatable {
    let hallId: String
    let bucket: String
    /// Zero until enough people are present that a number is not identifying.
    let headcount: Int
}

enum FriendDirection: String, Codable {
    case friend, incoming, outgoing
}

struct Friend: Codable, Identifiable, Equatable {
    let friendshipId: String
    let userId: String
    let displayName: String
    let username: String
    let emoji: String
    let status: String
    let direction: FriendDirection
    let notifyOn: Bool
    let labelIds: [String]

    var id: String { userId }
}

/// The result of looking someone up by number or username before adding them.
struct FoundPerson: Codable, Identifiable, Equatable {
    let id: String
    let displayName: String
    let username: String
    let emoji: String
    /// "none", "pending" or "accepted".
    let status: String
}

enum InviteReply: String, Codable, CaseIterable, Identifiable {
    case omw
    case inABit = "in_a_bit"
    case alreadyAte = "already_ate"
    case cant

    var id: String { rawValue }

    var label: String {
        switch self {
        case .omw:        return "On my way"
        case .inABit:     return "In a bit"
        case .alreadyAte: return "Already ate"
        case .cant:       return "Can't"
        }
    }

    var emoji: String {
        switch self {
        case .omw:        return "🏃"
        case .inABit:     return "⏳"
        case .alreadyAte: return "😮‍💨"
        case .cant:       return "🙅"
        }
    }
}

struct Invite: Codable, Identifiable, Equatable {
    let id: String
    let direction: String
    let otherId: String
    let otherName: String
    let otherEmoji: String
    let hallId: String
    let hallName: String
    let createdAt: Date
    let expiresAt: Date
    let response: String?
    let respondedAt: Date?

    var isIncoming: Bool { direction == "incoming" }
    var isAnswered: Bool { response != nil }
    var hasExpired: Bool { expiresAt < Date() }
    var reply: InviteReply? { response.flatMap(InviteReply.init(rawValue:)) }
}

struct FriendLabel: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let color: String
    let memberCount: Int
}

/// One thing that happened while you were not looking.
struct Alert: Codable, Equatable {
    let kind: String      // "arrival" | "invite" | "reply"
    let at: Date
    let otherName: String
    /// Hall name for arrivals and invites; the reply itself for replies.
    let hallName: String?
    let ref: String
}
