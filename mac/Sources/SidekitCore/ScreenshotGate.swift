import Foundation

/// Pure admission filter for screenshot auto-capture (spec 2026-06-12 §3.1): decides whether a
/// Spotlight-reported screenshot path gets shelved. Refuses the capture UI's hidden "fleeting"
/// dot-files, our own payload copies (a shelved screenshot keeps the screenshot attribute —
/// admitting it would loop copy → detect → copy), and recently-seen paths (each screenshot
/// lands exactly once). The recent list is a small FIFO so memory stays bounded.
public struct ScreenshotGate: Sendable {
    private let payloadRootPrefix: String
    private let capacity: Int
    private var recent: [String] = []

    public init(payloadRootPath: String, capacity: Int = 32) {
        // Trailing slash stops a sibling like …/ShelfOther from matching …/Shelf.
        self.payloadRootPrefix = payloadRootPath.hasSuffix("/") ? payloadRootPath
                                                                : payloadRootPath + "/"
        self.capacity = capacity
    }

    /// True exactly once per admissible path.
    public mutating func admit(_ path: String) -> Bool {
        guard let name = path.split(separator: "/").last, !name.hasPrefix(".") else { return false }
        guard !path.hasPrefix(payloadRootPrefix) else { return false }
        guard !recent.contains(path) else { return false }
        recent.append(path)
        if recent.count > capacity { recent.removeFirst(recent.count - capacity) }
        return true
    }
}
