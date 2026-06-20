import Foundation

/// Who this install belongs to, and where the soft-gate welcome stands (spec §2,
/// 2026-06-11 sign-up + feedback design). One small value persisted as identity.json.
public struct IdentityState: Sendable, Equatable, Codable {
    /// Normalized (trimmed, lowercased) sign-up email; nil until the user provides one.
    public var email: String?
    /// Total launches recorded (drives the 5th-launch re-ask).
    public var launchCount: Int
    /// How many times the welcome sheet auto-appeared (lifetime cap: 2).
    public var welcomeAutoShows: Int

    public init(email: String? = nil, launchCount: Int = 0, welcomeAutoShows: Int = 0) {
        self.email = email
        self.launchCount = launchCount
        self.welcomeAutoShows = welcomeAutoShows
    }
}

/// The "looks like an email" check (spec §2): one @, non-empty local part, dotted domain
/// with non-empty labels, no whitespace. Deliberately minimal — there is no verification.
public enum EmailCheck {
    public static func isPlausible(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(where: \.isWhitespace) else { return false }
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { !$0.isEmpty }
    }
}

/// Loads and saves the identity state. The store calls `load()` once at init and
/// `save(_:)` after every mutation; the adapter backs this with identity.json.
public protocol IdentityPersisting: Sendable {
    func load() -> IdentityState
    func save(_ state: IdentityState)
}

/// Owns the identity state and the soft-gate rule: the welcome sheet auto-shows on the
/// first launch; if skipped, once more on the 5th-or-later launch; never a third time,
/// and never once an email is set.
@MainActor
public final class IdentityStore {
    public private(set) var state: IdentityState
    private let persistence: IdentityPersisting

    public init(persistence: IdentityPersisting) {
        self.persistence = persistence
        self.state = persistence.load()
    }

    /// Call exactly once per app launch, before reading `shouldShowWelcome`.
    public func recordLaunch() {
        state.launchCount += 1
        persistence.save(state)
    }

    public var shouldShowWelcome: Bool {
        guard state.email == nil else { return false }
        if state.welcomeAutoShows == 0 { return true }
        return state.welcomeAutoShows == 1 && state.launchCount >= 5
    }

    /// Call when the sheet actually appears (counts toward the lifetime cap of 2).
    public func welcomeShown() {
        state.welcomeAutoShows += 1
        persistence.save(state)
    }

    /// Normalize and store a plausible email; returns false (no save) otherwise.
    @discardableResult
    public func setEmail(_ raw: String) -> Bool {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard EmailCheck.isPlausible(normalized) else { return false }
        state.email = normalized
        persistence.save(state)
        return true
    }

    /// Local-only removal (spec §2: no delete call to the backend).
    public func clearEmail() {
        state.email = nil
        persistence.save(state)
    }
}

/// Bytes ⇄ IdentityState, tolerant like the other codecs: corrupt/empty → fresh state.
public enum IdentityCodec {
    public static func encode(_ state: IdentityState) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(state)) ?? Data("{}".utf8)
    }

    public static func decode(_ data: Data) -> IdentityState {
        (try? JSONDecoder().decode(IdentityState.self, from: data)) ?? IdentityState()
    }
}
