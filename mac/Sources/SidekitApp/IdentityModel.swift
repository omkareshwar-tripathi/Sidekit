import Foundation
import Combine
import SidekitCore

/// Version strings attached to submissions (shown to the user in the feedback footer —
/// spec §3: everything sent is visible).
enum AppInfo {
    static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
    }

    static var osVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

/// SwiftUI-facing observable wrapper over the pure `IdentityStore` (NotesModel pattern).
/// A successfully stored email also queues a `signups` submission through the spool.
@MainActor
final class IdentityModel: ObservableObject {
    private let store: IdentityStore
    private let spool: SubmissionSpool

    var email: String? { store.state.email }
    var shouldShowWelcome: Bool { store.shouldShowWelcome }

    init(store: IdentityStore, spool: SubmissionSpool) {
        self.store = store
        self.spool = spool
    }

    func welcomeShown() {
        objectWillChange.send()
        store.welcomeShown()
    }

    /// Validate+store the email locally, then queue the sign-up write. Returns false
    /// (and changes nothing) when the text doesn't look like an email.
    @discardableResult
    func submitEmail(_ raw: String) -> Bool {
        objectWillChange.send()
        guard store.setEmail(raw) else { return false }
        guard let email = store.state.email else { return false }
        let submission = RemoteSubmission.signup(email: email, appVersion: AppInfo.appVersion)
        Task { await spool.enqueue(submission) }
        return true
    }

    /// Local-only (spec §2): no delete call to the backend.
    func clearEmail() {
        objectWillChange.send()
        store.clearEmail()
    }
}
