import Foundation
import SidekitCore

/// Where the two inserts go (spec §4). The anon key is public-by-design: row-level
/// security on the Supabase side allows INSERT only, so an extracted key cannot read,
/// list, or modify anything.
///
/// Fill the two constants from docs/SUPABASE-SETUP.md after creating the project.
/// The env overrides let a dev build point at a local stand-in server (M9 smoke test):
///   SIDEKIT_SUPABASE_URL=http://127.0.0.1:8765 SIDEKIT_SUPABASE_KEY=test swift run …
public enum SupabaseConfig {
    private static let defaultURL = ""      // e.g. "https://abcdefgh.supabase.co"
    private static let defaultAnonKey = ""  // the project's anon/public key

    public static var projectURL: URL? {
        let raw = ProcessInfo.processInfo.environment["SIDEKIT_SUPABASE_URL"] ?? defaultURL
        return raw.isEmpty ? nil : URL(string: raw)
    }

    public static var anonKey: String {
        ProcessInfo.processInfo.environment["SIDEKIT_SUPABASE_KEY"] ?? defaultAnonKey
    }
}

/// The app's one network adapter: POST a submission's body to its PostgREST table.
/// `Prefer: return=minimal` keeps insert-only RLS sufficient (no select needed).
public struct SupabaseSubmissionSender: SubmissionSending {
    public init() {}

    public func send(_ submission: RemoteSubmission) async -> SendResult {
        // Unconfigured build (no URL baked in, no env override): keep everything queued —
        // nothing is lost, and a configured build will flush the spool on launch.
        guard let base = SupabaseConfig.projectURL else { return .retryable }
        var request = URLRequest(url: base.appendingPathComponent("rest/v1/\(submission.table)"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.httpBody = submission.jsonBody()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .retryable }
            switch http.statusCode {
            case 200..<300:
                return .sent
            case 409 where submission.table == "signups":
                return .sent // duplicate email — already on the list, goal met (spec §4)
            case 400..<500:
                return .rejected
            default:
                return .retryable // 5xx — Supabase hiccup, try again next launch
            }
        } catch {
            return .retryable // offline / timeout — the spool holds it (spec §6)
        }
    }
}
