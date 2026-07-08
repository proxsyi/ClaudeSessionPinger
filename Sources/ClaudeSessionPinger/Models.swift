import Foundation

struct PingRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let success: Bool
    let summary: String
}

struct ScheduleSlot: Codable, Equatable {
    var hour: Int
    var minute: Int
}

enum PingStatus: Equatable {
    case idle
    case sending
    case success
    case failure
}

struct PingOutcome {
    let conversationID: String
    let replyText: String
    let matchedExpected: Bool
}
