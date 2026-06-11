import Foundation

/// The optional feedback tag (spec §3): the 🐞/💡 chips; untagged lands as `.other`.
/// Raw values match the `feedback.type` check constraint in Supabase.
public enum FeedbackKind: String, Sendable, Equatable, Codable {
    case bug, feature, other
}

/// One outbound write — the only data Sidekit ever sends anywhere (spec §1 decision 5).
/// Knows its target table and its exact JSON body, so the network adapter stays a dumb pipe
/// and the wire format is unit-tested here. Codable so the spool can persist it.
/// (The synthesized case/label names are the persisted outbox format — don't rename them.)
public enum RemoteSubmission: Sendable, Equatable, Codable {
    case signup(email: String, appVersion: String)
    case feedback(kind: FeedbackKind, message: String, email: String?,
                  appVersion: String, osVersion: String)

    /// Hard cap on a feedback message (mirrors the DB check constraint).
    public static let feedbackMessageLimit = 4000

    /// Trimmed message if sendable (non-blank, within the cap), else nil.
    /// Counts unicode scalars to match Postgres `char_length` (code points), so a
    /// client-approved message can never trip the server's check constraint.
    public static func validateFeedbackMessage(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.count <= feedbackMessageLimit else { return nil }
        return trimmed
    }

    /// The PostgREST table this submission inserts into.
    public var table: String {
        switch self {
        case .signup: return "signups"
        case .feedback: return "feedback"
        }
    }

    /// The exact insert body. Keys match the table columns (spec §4).
    public func jsonBody() -> Data {
        var object: [String: String]
        switch self {
        case let .signup(email, appVersion):
            object = ["email": email, "app_version": appVersion, "platform": "mac"]
        case let .feedback(kind, message, email, appVersion, osVersion):
            object = ["type": kind.rawValue, "message": message,
                      "app_version": appVersion, "os_version": osVersion]
            if let email { object["email"] = email }
        }
        return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data("{}".utf8)
    }
}
