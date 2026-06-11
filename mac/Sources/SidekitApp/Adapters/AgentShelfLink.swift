import Foundation

/// Launch-time keeper of the agent-facing path: `~/.sidekit/shelf` → the real payload folder
/// (spec 2026-06-12 §2.1). Returns the path to advertise in the copy-instructions prompt — the
/// short symlink normally, the real folder when the site is occupied by something that isn't a
/// symlink (left untouched: never delete what we didn't create).
enum AgentShelfLink {
    @discardableResult
    static func ensure(realFolder: URL,
                       home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let fm = FileManager.default
        let dir = home.appendingPathComponent(".sidekit", isDirectory: true)
        let link = dir.appendingPathComponent("shelf")
        let display = "~/.sidekit/shelf"

        // attributesOfItem does not traverse the final symlink — safe to inspect the site itself.
        if let kind = try? fm.attributesOfItem(atPath: link.path)[.type] as? FileAttributeType {
            guard kind == .typeSymbolicLink else {
                Diag.log("agent link: \(link.path) exists and is not a symlink — leaving it")
                return realFolder.path
            }
            if (try? fm.destinationOfSymbolicLink(atPath: link.path)) == realFolder.path {
                return display
            }
            try? fm.removeItem(at: link) // our stale link — repoint below
        }
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.createSymbolicLink(at: link, withDestinationURL: realFolder)
            return display
        } catch {
            Diag.log("agent link: could not create \(link.path) (\(error))")
            return realFolder.path
        }
    }
}
