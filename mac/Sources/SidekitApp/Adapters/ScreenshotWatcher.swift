import Foundation
import SidekitCore

/// Watches Spotlight for new macOS screenshots and feeds them to the Shelf (spec 2026-06-12 §3).
/// `NSMetadataQuery` for `kMDItemIsScreenCapture == 1`, home-scoped — catches the built-in
/// capture UI wherever its save location points, in any system language. The initial gather
/// (every screenshot already on disk) never reaches us: `NSMetadataQueryDidUpdate` only fires in
/// the live-update phase, after gathering — so there's no "skip the backlog" flag to manage.
/// Each candidate passes the pure `ScreenshotGate`, then a short stability re-check (the capture
/// UI shows a floating preview before the final file settles), then is copied in through the
/// same ingest path as a drag-in. First detection under ~/Desktop triggers macOS's one-time
/// folder-access consent; if denied, the query simply never reports those files (spec §3.3).
@MainActor
final class ScreenshotWatcher {
    private let query = NSMetadataQuery()
    private var gate: ScreenshotGate
    private let ingest: (URL) -> Void
    private var observer: NSObjectProtocol?

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
