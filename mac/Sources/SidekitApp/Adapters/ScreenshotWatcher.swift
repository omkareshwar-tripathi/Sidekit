import Foundation
import SidekitCore

/// Watches Spotlight for new macOS screenshots and feeds them to the Shelf (spec 2026-06-12 §3).
/// `NSMetadataQuery` for `kMDItemIsScreenCapture == 1`, home-scoped — catches the built-in
/// capture UI wherever its save location points, in any system language. The initial gather
/// (every screenshot already on disk) never reaches us: `NSMetadataQueryDidUpdate` only fires in
/// the live-update phase, after gathering — so there's no "skip the backlog" flag to manage.
/// Each candidate passes the pure `ScreenshotGate`, then a short stability re-check (the capture
/// UI shows a floating preview before the final file settles), then is copied in through the
/// same ingest path as a drag-in.
///
/// Desktop consent (debugged live 2026-06-12): Spotlight silently FILTERS results from
/// TCC-protected folders, and a metadata query alone never trips the consent dialog — the app
/// never touches ~/Desktop directly, so macOS never asks and Desktop screenshots can never land.
/// `start()` therefore touches the Desktop once per launch (off-main; the call blocks until the
/// user answers) and restarts the query after the answer so a fresh grant applies immediately.
/// If denied, the query simply never reports those files (spec §3.3) — re-enable in System
/// Settings → Privacy & Security → Files & Folders.
@MainActor
final class ScreenshotWatcher {
    private let query = NSMetadataQuery()
    private var gate: ScreenshotGate
    private let ingest: (URL) -> Void
    private var observer: NSObjectProtocol?
    private var desktopTouched = false

    init(payloadRoot: URL, ingest: @escaping (URL) -> Void) {
        self.gate = ScreenshotGate(payloadRootPath: payloadRoot.standardizedFileURL.path)
        self.ingest = ingest
    }

    func start() {
        guard observer == nil else { return } // already running
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
            let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
            let paths = added.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }
            // queue: .main ⇒ main actor (house pattern, cf. ShelfDragStartMonitor).
            MainActor.assumeIsolated { self?.consider(paths) }
        }
        query.start()
        touchDesktopOnce()
    }

    /// Trigger the one-time Desktop folder-consent prompt (see the type comment). Runs once per
    /// launch; `contentsOfDirectory` blocks until the user answers, so it stays off the main
    /// actor. Afterwards the query restarts (if still on) so the grant takes effect mid-session.
    private func touchDesktopOnce() {
        guard !desktopTouched else { return }
        desktopTouched = true
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop", isDirectory: true).path
        Task.detached(priority: .utility) {
            let entries = try? FileManager.default.contentsOfDirectory(atPath: desktop)
            Diag.log("screenshot: desktop touch → " +
                     (entries.map { "\($0.count) entries (access OK)" } ?? "denied/unreadable"))
            await MainActor.run { [weak self] in
                guard let self, self.observer != nil else { return }
                self.stop()
                self.start() // desktopTouched guards re-entry into this method
            }
        }
    }

    func stop() {
        guard let observer else { return }
        query.stop()
        NotificationCenter.default.removeObserver(observer)
        self.observer = nil
    }

    private func consider(_ paths: [String]) {
        for path in paths where gate.admit(path) { shelveWhenStable(path) }
    }

    /// Single re-check (spec §3.1): shelve only if the file still exists ~1.5 s later with the
    /// same nonzero size; anything else is logged and skipped — never retry-looped (spec §5).
    private func shelveWhenStable(_ path: String) {
        let size: () -> Int64? = { (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int64 }
        guard let first = size(), first > 0 else {
            Diag.log("screenshot: skipped empty/missing \(path)")
            return
        }
        Task { @MainActor [ingest] in
            try? await Task.sleep(for: .seconds(1.5))
            guard size() == first else {
                Diag.log("screenshot: skipped unstable \(path)")
                return
            }
            ingest(URL(fileURLWithPath: path))
            Diag.log("screenshot: shelved \(path.split(separator: "/").last.map(String.init) ?? path)")
        }
    }
}
