# Shelf for Agents + Auto-Screenshots Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Any AI agent can read the Sidekit Shelf through a stable folder + manifest, and macOS screenshots land on the Shelf automatically.

**Architecture:** Spec `docs/superpowers/specs/2026-06-12-sidekit-shelf-agents-screenshots-design.md`. Ports-and-adapters, house style: two new pure core units (`ShelfManifest` codec, `ScreenshotGate` filter) TDD'd in `SidekitCore`; three thin adapters (`AgentManifestShelfStore` persistence decorator, `AgentShelfLink` symlink keeper, `ScreenshotWatcher` Spotlight query) in `SidekitApp`; small UI touches (Shelf footer button, Settings toggle). Zero changes to `ShelfStore` — the decorator rides the existing `ShelfPersisting.save(items)` funnel.

**Tech Stack:** Swift 6 / SwiftPM (`mac/`), swift-testing (`@Test`/`#expect`), SwiftUI, `NSMetadataQuery` (Spotlight). All commands run from `mac/`.

**House rules that apply to every task:** CLAUDE.md §2a brick loop (review diff → test → verify → move on), §3 surgical scope, §2b BRICKS.md updates (consolidated entry in Task 6, matching the SHIP-1..7 precedent). Baseline before Task 1: `swift test` = **140/140**.

---

### Task 1: `ShelfManifest` core codec (TDD)

The pure codec for everything agent-facing: `manifest.json` bytes, the `AGENTS.md` body, and the clipboard prompt. Token-budgeted strings come verbatim from spec §2.3/§2.4 — do not reword them.

**Files:**
- Create: `mac/Sources/SidekitCore/ShelfManifest.swift`
- Test: `mac/Tests/SidekitCoreTests/ShelfManifestTests.swift`

Skill: none (no Swift domain skill per CLAUDE.md §6; superpowers:test-driven-development applies)

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
import Foundation
@testable import SidekitCore

struct ShelfManifestTests {
    // Whole-second dates: the manifest serializes ISO-8601 without fractional seconds.
    private let t0 = Date(timeIntervalSince1970: 1_786_000_000)

    private func item(name: String = "shot.png", addedAt: Date,
                      path: String = "u1/shot.png") -> ShelfItem {
        ShelfItem(kind: .file, displayName: name, byteSize: 7, addedAt: addedAt,
                  storedRelativePath: path)
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func emptyShelfStillProducesValidManifest() throws {
        let root = try decode(ShelfManifest.json(items: [], retention: .default, now: t0))
        #expect(root["schema"] as? Int == 1)
        #expect((root["items"] as? [Any])?.isEmpty == true)
        #expect(root["updatedAt"] as? String != nil)
    }

    @Test func entryCarriesAllAgentFacingFields() throws {
        let it = item(addedAt: t0)
        let root = try decode(ShelfManifest.json(items: [it], retention: .default, now: t0))
        let entry = try #require((root["items"] as? [[String: Any]])?.first)
        #expect(entry["id"] as? String == it.id.uuidString)
        #expect(entry["kind"] as? String == "file")
        #expect(entry["name"] as? String == "shot.png")
        #expect(entry["bytes"] as? Int == 7)
        #expect(entry["path"] as? String == "u1/shot.png")
        // expiresAt = addedAt + 48h (the default retention)
        let expires = try #require(entry["expiresAt"] as? String)
        let parsed = try #require(ISO8601DateFormatter().date(from: expires))
        #expect(parsed == t0.addingTimeInterval(48 * 3600))
    }

    @Test func itemsAreNewestFirst() throws {
        let old = item(name: "old", addedAt: t0)
        let new = item(name: "new", addedAt: t0.addingTimeInterval(60))
        let root = try decode(ShelfManifest.json(items: [old, new], retention: .default, now: t0))
        let names = (root["items"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        #expect(names == ["new", "old"])
    }

    @Test func neverExpireWritesExplicitNull() throws {
        let root = try decode(ShelfManifest.json(items: [item(addedAt: t0)],
                                                 retention: ShelfRetentionPolicy(ttl: nil), now: t0))
        let entry = try #require((root["items"] as? [[String: Any]])?.first)
        // The key must be PRESENT with a JSON null — agents rely on it (spec §2.2).
        #expect(entry.keys.contains("expiresAt"))
        #expect(entry["expiresAt"] is NSNull)
    }

    @Test func outputIsDeterministic() {
        let items = [item(addedAt: t0)]
        let a = ShelfManifest.json(items: items, retention: .default, now: t0)
        let b = ShelfManifest.json(items: items, retention: .default, now: t0)
        #expect(a == b)
    }

    @Test func instructionsEmbedTheAdvertisedPath() {
        let prompt = ShelfManifest.instructions(path: "~/.sidekit/shelf")
        #expect(prompt.contains("~/.sidekit/shelf"))
        #expect(prompt.contains("manifest.json"))
        #expect(prompt.contains("Read-only"))
    }

    @Test func agentsNoteIsTokenLean() {
        // Budget guard (spec §1): the note agents read into context stays tiny.
        #expect(ShelfManifest.agentsNote.count < 400)
        #expect(ShelfManifest.agentsNote.contains("manifest.json"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ShelfManifestTests`
Expected: compile FAILURE — `cannot find 'ShelfManifest' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// Pure codec for the agent-facing Shelf contract (spec 2026-06-12 §2): the `manifest.json`
/// bytes, the static `AGENTS.md` body, and the clipboard prompt. No I/O — the persistence
/// decorator owns the files; this owns only `[ShelfItem]` + retention → bytes. Mirrors
/// `ShelfCodec`. Output is deterministic (sorted keys, ISO-8601 dates, injected `now`) so
/// repeated writes of an unchanged shelf are byte-identical.
///
/// All agent-facing strings are token-budgeted (user decision): agents read them into
/// context on every use, so keep them short — don't "improve" the wording.
public enum ShelfManifest {
    public static let schema = 1

    /// The static `AGENTS.md` placed beside the manifest (spec §2.3).
    public static let agentsNote = """
    # Sidekit Shelf
    Files the user parked in Sidekit. Read-only: do not add, edit, or delete anything here.
    List items: read `manifest.json` (newest first; each `path` is relative to this folder).
    Items expire (`expiresAt`) — re-read `manifest.json` before each use.
    """

    /// The paste-ready prompt behind the footer's copy action (spec §2.4). `path` is the
    /// advertised folder — `~/.sidekit/shelf` normally, the real folder when no symlink.
    public static func instructions(path: String) -> String {
        "The Sidekit Shelf is at \(path). Read manifest.json there to list items "
        + "(newest first; `path` is relative to that folder), then read the files you need. Read-only."
    }

    /// The `manifest.json` bytes for the current shelf. `expiresAt` is computed from the
    /// retention TTL at write time; "never expire" writes an explicit `null` (key always present).
    public static func json(items: [ShelfItem], retention: ShelfRetentionPolicy, now: Date) -> Data {
        let ttl = retention.ttl.map { Double($0.components.seconds) }
        let entries = items.sorted { $0.addedAt > $1.addedAt }.map { item in
            Entry(id: item.id.uuidString, kind: item.kind.rawValue, name: item.displayName,
                  addedAt: item.addedAt,
                  expiresAt: ttl.map { item.addedAt.addingTimeInterval($0) },
                  bytes: item.byteSize, path: item.storedRelativePath)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(Root(schema: schema, updatedAt: now, items: entries))) ?? Data()
    }

    private struct Root: Encodable {
        let schema: Int
        let updatedAt: Date
        let items: [Entry]
    }

    private struct Entry: Encodable {
        let id: String
        let kind: String
        let name: String
        let addedAt: Date
        let expiresAt: Date?
        let bytes: Int64
        let path: String

        // Hand-written so a nil `expiresAt` encodes as an explicit JSON null — synthesized
        // Encodable would drop the key, and agents rely on its presence (spec §2.2).
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id)
            try c.encode(kind, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(addedAt, forKey: .addedAt)
            try c.encode(expiresAt, forKey: .expiresAt) // Optional encodes nil as null
            try c.encode(bytes, forKey: .bytes)
            try c.encode(path, forKey: .path)
        }
        private enum CodingKeys: String, CodingKey {
            case id, kind, name, addedAt, expiresAt, bytes, path
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ShelfManifestTests` → 7 pass. Then full `swift test` → **147/147**.

- [ ] **Step 5: Commit**

```bash
git add Sources/SidekitCore/ShelfManifest.swift Tests/SidekitCoreTests/ShelfManifestTests.swift
git commit -m "feat(mac): ShelfManifest codec — agent-facing manifest/AGENTS.md/prompt (TDD)"
```

---

### Task 2: `AgentManifestShelfStore` decorator + `ShelfModel` wiring

The decorator keeps `manifest.json` + `AGENTS.md` in sync with every index save. Wired only in `ShelfModel`'s **production** convenience init — the designated init (used by tests) is untouched.

**Files:**
- Create: `mac/Sources/SidekitApp/Adapters/AgentManifestShelfStore.swift`
- Modify: `mac/Sources/SidekitApp/ShelfModel.swift` (properties at top; `convenience init()`; `setRetentionTTL`)

Skill: none (verification-before-completion)

- [ ] **Step 1: Write the adapter**

```swift
import Foundation
import SidekitCore

/// `ShelfPersisting` decorator that keeps the agent-facing files in the payload folder in sync
/// with every index save (spec 2026-06-12 §2.2): `manifest.json` on each `save`, `AGENTS.md`
/// once if missing. Both are derived state — a failed write is Diag-logged and healed by the
/// next save, never fatal.
///
/// `@unchecked Sendable`: `retention` is read/written only on the main actor (saves are
/// synchronous on the caller, same discipline as `JSONShelfStore`); the rest is immutable.
final class AgentManifestShelfStore: ShelfPersisting, @unchecked Sendable {
    private let inner: ShelfPersisting
    private let folder: URL
    private let now: () -> Date
    /// Drives each entry's `expiresAt`; updated by `ShelfModel.setRetentionTTL`.
    var retention: ShelfRetentionPolicy = .default

    init(inner: ShelfPersisting, folder: URL, now: @escaping () -> Date = { Date() }) {
        self.inner = inner
        self.folder = folder
        self.now = now
    }

    func load() -> [ShelfItem] { inner.load() }

    func save(_ items: [ShelfItem]) {
        inner.save(items)
        writeAgentFiles(items)
    }

    /// Also called at startup (fresh install; heals a manual delete) and on retention changes
    /// (so `expiresAt` doesn't go stale) — see `ShelfModel`.
    func writeAgentFiles(_ items: [ShelfItem]) {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try ShelfManifest.json(items: items, retention: retention, now: now())
                .write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
            let agents = folder.appendingPathComponent("AGENTS.md")
            if !FileManager.default.fileExists(atPath: agents.path) {
                try Data(ShelfManifest.agentsNote.utf8).write(to: agents, options: .atomic)
            }
        } catch {
            Diag.log("shelf: agent files write failed (\(error))")
        }
    }
}
```

- [ ] **Step 2: Wire it in `ShelfModel`**

Add one property below `private let payloadStore: ShelfPayloadStore`:

```swift
    /// Set by the production init — lets retention changes refresh the manifest's `expiresAt`.
    private var manifestStore: AgentManifestShelfStore?
```

Replace the production `convenience init()` body:

```swift
    convenience init() {
        let payloads = FileSystemShelfPayloadStore()
        let folder = AppPaths.applicationSupport.appendingPathComponent("Shelf", isDirectory: true)
        let manifest = AgentManifestShelfStore(inner: JSONShelfStore(), folder: folder)
        self.init(store: ShelfStore(persistence: manifest, payloads: payloads), payloadStore: payloads)
        self.manifestStore = manifest
        manifest.writeAgentFiles(items) // exists on a fresh install; heals a manual delete
    }
```

In `setRetentionTTL`, keep the manifest's `expiresAt` honest (prune only saves when something
actually expired, so force a rewrite):

```swift
    func setRetentionTTL(_ ttl: Duration?) {
        store.retention = ShelfRetentionPolicy(ttl: ttl)
        manifestStore?.retention = ShelfRetentionPolicy(ttl: ttl)
        prune()
        manifestStore?.writeAgentFiles(items)
    }
```

- [ ] **Step 3: Build + behavior check**

Run: `swift build && swift test` → builds clean, still **147/147** (core untouched).
Then verify the files appear and stay in sync without launching the UI:

```bash
swift run Sidekit & sleep 8; kill %1
cat "$HOME/Library/Application Support/Sidekit/Shelf/manifest.json"
cat "$HOME/Library/Application Support/Sidekit/Shelf/AGENTS.md"
```

Expected: a valid manifest (`"schema" : 1`, `items` mirroring the user's current shelf — entries match `shelf.json`) and the 4-line AGENTS.md. (If `swift run` can't grab the Fn monitor without Accessibility for the dev binary, fall back to `Scripts/build-app.sh` + open the app once.)

- [ ] **Step 4: Commit**

```bash
git add Sources/SidekitApp/Adapters/AgentManifestShelfStore.swift Sources/SidekitApp/ShelfModel.swift
git commit -m "feat(mac): manifest-writing shelf persistence decorator — agent files ride every save"
```

---

### Task 3: `AgentShelfLink` symlink + "For agents" copy action

The short path agents are told about, and the one-click onboarding.

**Files:**
- Create: `mac/Sources/SidekitApp/Adapters/AgentShelfLink.swift`
- Modify: `mac/Sources/SidekitApp/ShelfModel.swift` (property + production init + new method)
- Modify: `mac/Sources/SidekitApp/ShelfView.swift` (`ShelfFooter` at ~line 516; call site at ~line 91)

Skill: none (verification-before-completion)

- [ ] **Step 1: Write the symlink keeper**

```swift
import Foundation
import SidekitCore

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
```

- [ ] **Step 2: Advertise + copy from `ShelfModel`**

Property below `manifestStore`:

```swift
    /// The folder agents are told about — the symlink normally, the real folder as fallback.
    private(set) var agentPath = "~/.sidekit/shelf"
```

In the production `convenience init()`, after `manifest.writeAgentFiles(items)`:

```swift
        self.agentPath = AgentShelfLink.ensure(realFolder: folder)
```

New method next to `copyToClipboard`:

```swift
    /// Put the paste-ready agent prompt on the clipboard (spec §2.4) — the whole onboarding
    /// for Claude Code / Antigravity / any agent that can read files.
    func copyAgentInstructions() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ShelfManifest.instructions(path: agentPath), forType: .string)
    }
```

- [ ] **Step 3: Footer button**

`ShelfFooter` (~line 516) gains a closure + brief "Copied ✓" feedback (same pattern as the
existing plain caption buttons — match their styling exactly):

```swift
private struct ShelfFooter: View {
    let count: Int
    let totalBytes: Int64
    let onSaveAll: () -> Void
    let onClearAll: () -> Void
    let onCopyAgent: () -> Void
    @State private var copiedAgent = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text("\(count) \(count == 1 ? "item" : "items") · \(sizeText)")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Spacer()
            Button(copiedAgent ? "Copied ✓" : "For agents") {
                onCopyAgent()
                copiedAgent = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copiedAgent = false }
            }
            .buttonStyle(.plain)
            .font(DS.Typography.caption)
            .foregroundStyle(DS.Palette.textSecondary)
            .help("Copy instructions that let any AI agent read this Shelf")
            Button("Save all to…") { onSaveAll() }
                .buttonStyle(.plain)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
            Button("Clear all") { onClearAll() }
                .buttonStyle(.plain)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Palette.textSecondary)
        }
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}
```

Call site (~line 91) gains the argument:

```swift
                ShelfFooter(count: model.items.count,
                            totalBytes: model.totalByteSize,
                            onSaveAll: saveAll,
                            onClearAll: { selection.removeAll(); model.clearAll() },
                            onCopyAgent: { model.copyAgentInstructions() })
```

- [ ] **Step 4: Build + verify the link and the prompt**

```bash
swift build && swift test          # clean, 147/147
swift run Sidekit & sleep 8; kill %1
ls -la ~/.sidekit/                 # shelf -> …/Application Support/Sidekit/Shelf
cat ~/.sidekit/shelf/manifest.json # readable THROUGH the link
```

UI check (signed build or next manual pass): Shelf panel footer shows "For agents"; clicking
flips to "Copied ✓" and `pbpaste` prints the prompt with `~/.sidekit/shelf` in it.

- [ ] **Step 5: Commit**

```bash
git add Sources/SidekitApp/Adapters/AgentShelfLink.swift Sources/SidekitApp/ShelfModel.swift Sources/SidekitApp/ShelfView.swift
git commit -m "feat(mac): ~/.sidekit/shelf agent symlink + footer 'For agents' copy action"
```

---

### Task 4: `ScreenshotGate` core filter (TDD)

Pure admission logic: each screenshot shelved exactly once; fleeting dot-files and our own
payload copies refused (a shelved copy keeps the Spotlight screenshot attribute — without the
root check the watcher would loop copy → detect → copy).

**Files:**
- Create: `mac/Sources/SidekitCore/ScreenshotGate.swift`
- Test: `mac/Tests/SidekitCoreTests/ScreenshotGateTests.swift`

Skill: none (superpowers:test-driven-development)

- [ ] **Step 1: Write the failing tests**

```swift
import Testing
@testable import SidekitCore

struct ScreenshotGateTests {
    private func gate(capacity: Int = 32) -> ScreenshotGate {
        ScreenshotGate(payloadRootPath: "/Users/o/Library/Application Support/Sidekit/Shelf",
                       capacity: capacity)
    }

    @Test func admitsANewScreenshotExactlyOnce() {
        var g = gate()
        #expect(g.admit("/Users/o/Desktop/Screenshot 1.png") == true)
        #expect(g.admit("/Users/o/Desktop/Screenshot 1.png") == false)
    }

    @Test func refusesHiddenFleetingFiles() {
        var g = gate()
        #expect(g.admit("/Users/o/Desktop/.Screenshot 1.png") == false)
    }

    @Test func refusesOurOwnPayloadCopies() {
        var g = gate()
        let stored = "/Users/o/Library/Application Support/Sidekit/Shelf/u1/Screenshot 1.png"
        #expect(g.admit(stored) == false)
    }

    @Test func payloadRootMatchIsPrefixSafe() {
        // A sibling like …/ShelfOther must not match …/Shelf (same rule as the payload store).
        var g = gate()
        #expect(g.admit("/Users/o/Library/Application Support/Sidekit/ShelfOther/x.png") == true)
    }

    @Test func capacityEvictsOldestFirstSoItCanLandAgain() {
        var g = gate(capacity: 2)
        #expect(g.admit("/d/a.png") == true)
        #expect(g.admit("/d/b.png") == true)
        #expect(g.admit("/d/c.png") == true)  // evicts a.png from memory
        #expect(g.admit("/d/a.png") == true)  // forgotten → admissible again
        #expect(g.admit("/d/c.png") == false) // still remembered
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ScreenshotGateTests`
Expected: compile FAILURE — `cannot find 'ScreenshotGate' in scope`.

- [ ] **Step 3: Write the implementation**

```swift
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ScreenshotGateTests` → 5 pass. Full `swift test` → **152/152**.

- [ ] **Step 5: Commit**

```bash
git add Sources/SidekitCore/ScreenshotGate.swift Tests/SidekitCoreTests/ScreenshotGateTests.swift
git commit -m "feat(mac): ScreenshotGate — once-only admission with payload-store loop guard (TDD)"
```

---

### Task 5: `ScreenshotWatcher` + Settings toggle + app wiring

The Spotlight query adapter, the "Auto-add screenshots to Shelf" toggle (ON by default), and the
wiring that routes detections through the exact same ingest path as a drag-in.

**Files:**
- Create: `mac/Sources/SidekitApp/Adapters/ScreenshotWatcher.swift`
- Modify: `mac/Sources/SidekitApp/SettingsPanel.swift` (`SettingsModel` + the Shelf `Section`)
- Modify: `mac/Sources/SidekitApp/App.swift` (`AppController` property ~line 162; init ~line 175 and ~line 227)

Skill: none (verification-before-completion)

- [ ] **Step 1: Write the watcher**

```swift
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
        let size = { (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int64 }
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
```

- [ ] **Step 2: Settings toggle**

`SettingsModel` — new published property after `shelfTTLSeconds` (same didSet pattern), new key +
closure after `applyShelfTTL`, new init parameter, seed at the end of init:

```swift
    /// Auto-add macOS screenshots to the Shelf (spec 2026-06-12 §3.3; default ON).
    @Published var autoShelfScreenshots: Bool {
        didSet {
            UserDefaults.standard.set(autoShelfScreenshots, forKey: Self.screenshotsKey)
            applyScreenshotCapture(autoShelfScreenshots)
        }
    }
```

```swift
    private static let screenshotsKey = "AutoShelfScreenshots"
    /// Starts/stops the live screenshot watcher.
    private let applyScreenshotCapture: @MainActor (Bool) -> Void
```

Init signature and body additions (assignments before first use, seed call at the end with the
other two seeds):

```swift
    init(applySettings: @escaping @MainActor (SidekitCore.Settings) -> Void,
         applyShelfTTL: @escaping @MainActor (Duration?) -> Void,
         applyScreenshotCapture: @escaping @MainActor (Bool) -> Void) {
        ...
        self.applyScreenshotCapture = applyScreenshotCapture
        let shots = UserDefaults.standard.object(forKey: Self.screenshotsKey) as? Bool ?? true
        self.autoShelfScreenshots = shots // init assignment → didSet does not fire
        ...
        applyScreenshotCapture(shots) // seed: starts the watcher when enabled (default on)
    }
```

`SettingsView`, Shelf section — toggle above the picker:

```swift
                Section("Shelf") {
                    Toggle("Auto-add screenshots to Shelf", isOn: $model.autoShelfScreenshots)
                    Picker("Keep items for", selection: $model.shelfTTLSeconds) {
```

- [ ] **Step 3: App wiring**

`AppController` — property near `shelfDragMonitor` (~line 162):

```swift
    private let screenshotWatcher: ScreenshotWatcher
```

In `init()`, right after `let shelf = ShelfModel()` (~line 175):

```swift
        // Auto-shelf screenshots (spec 2026-06-12 §3): detections take the same copy-in
        // path as a drag-in, so TTL / thumbnails / drag-out all just work.
        let screenshots = ScreenshotWatcher(
            payloadRoot: AppPaths.applicationSupport.appendingPathComponent("Shelf", isDirectory: true),
            ingest: { url in shelf.ingest(.file(url)) })
```

Extend the `SettingsModel` call (~line 227) and store the watcher with the other assignments:

```swift
        let settings = SettingsModel(
            applySettings: { [weak coordinator] s in coordinator?.settings = s },
            applyShelfTTL: { ttl in shelf.setRetentionTTL(ttl) },
            applyScreenshotCapture: { on in on ? screenshots.start() : screenshots.stop() })
```

```swift
        self.screenshotWatcher = screenshots
```

- [ ] **Step 4: Build + live verify (machine-drivable)**

```bash
swift build && swift test                          # clean, 152/152
Scripts/build-app.sh release && open <built .app>  # the signed app, real run
sleep 5
screencapture -x "$HOME/Desktop/sidekit-m10-probe.png"
sleep 4
grep -o '"name" *: *"[^"]*"' "$HOME/Library/Application Support/Sidekit/Shelf/manifest.json"
```

Expected: the probe appears in the manifest (and as a Shelf tile with a thumbnail), exactly once.
If `screencapture` output lacks the Spotlight attribute on this machine (`mdls -name
kMDItemIsScreenCapture ~/Desktop/sidekit-m10-probe.png` → 0/missing), fall back to a real ⌘⇧3 in
the manual pass and note it. Clean up: `rm ~/Desktop/sidekit-m10-probe.png` + remove the tile.

- [ ] **Step 5: Commit**

```bash
git add Sources/SidekitApp/Adapters/ScreenshotWatcher.swift Sources/SidekitApp/SettingsPanel.swift Sources/SidekitApp/App.swift
git commit -m "feat(mac): screenshots auto-land on the Shelf — Spotlight watcher + Settings toggle (default on)"
```

---

### Task 6: TESTING.md M10 + BRICKS.md + acceptance pass

**Files:**
- Modify: `mac/TESTING.md` (new §10 + update the intro count)
- Modify: `BRICKS.md` (consolidated Done entry; remove the two bricks from Next up; archive rotation per §2b)

Skill: none (superpowers:verification-before-completion)

- [ ] **Step 1: Add `TESTING.md` §10 — M10: Shelf for agents + auto-screenshots**

Checks to write (same table style as §9):

| ID | Check | Expected |
|---|---|---|
| m10-1 | ⌘⇧3 with capture ON | tile appears once, correct thumbnail; manifest gains the entry |
| m10-2 | Settings → toggle OFF → ⌘⇧3 | nothing lands |
| m10-3 | toggle back ON → ⌘⇧3 | lands again (watcher restarts) |
| m10-4 | `ls -la ~/.sidekit` | `shelf` symlink → the real folder; `manifest.json` + `AGENTS.md` readable through it |
| m10-5 | remove a tile / Clear all | entry disappears from `manifest.json` |
| m10-6 | retention change in Settings | every `expiresAt` in the manifest shifts accordingly |
| m10-7 | footer "For agents" → paste into any agent (Claude Code) | agent lists the items and reads one (the acceptance test) |
| m10-8 | first-ever capture | macOS Desktop-folder consent appears once; deny → no tile, no crash (re-allow in System Settings → Files & Folders) |

- [ ] **Step 2: Acceptance run (m10-7 for real)**

Paste the copied instructions into a fresh Claude Code session; have it list the Shelf and read
one item's content back. Capture the transcript snippet as evidence.

- [ ] **Step 3: Update BRICKS.md**

One consolidated Done entry (SHIP-1..7 precedent): what shipped, files, verification (test count
delta 140→152, M10 results), notes (symlink fallback rule, the copy→detect loop guard, accepted
limits from spec §3.3). Remove **SHELF-AGENTS** + **SHELF-SCREENSHOTS** from "Next iterations";
keep Done at 3 entries (archive the oldest to `BRICKS-ARCHIVE.md` verbatim).

- [ ] **Step 4: Commit**

```bash
git add mac/TESTING.md BRICKS.md BRICKS-ARCHIVE.md
git commit -m "docs(mac): M10 agent-shelf + screenshots checks; BRICKS entry for the shelf pair"
```

---

## Self-review notes (done at write time)

- **Spec coverage:** §2.1 symlink → Task 3; §2.2 manifest + decorator + startup/retention rewrites → Tasks 1–2; §2.3 AGENTS.md → Tasks 1–2; §2.4 copy action → Task 3; §3.1 detection/initial-gather/stability/dedup → Tasks 4–5; §3.2 same-ingest-path landing → Task 5; §3.3 toggle/consent/limits → Tasks 5–6; §5 error rules → embedded in each adapter; §6 tests → Tasks 1, 4, 6. No gaps.
- **Type consistency:** `ShelfManifest.instructions(path:)`/`agentsNote`/`json(items:retention:now:)` used identically in Tasks 1–3; `ScreenshotGate(payloadRootPath:capacity:)`/`admit(_:)` in Tasks 4–5; `AgentManifestShelfStore.writeAgentFiles(_:)`/`retention` in Tasks 2–3. `ShelfPersisting` has a default `flush()` — the decorator inherits it; `inner` is `JSONShelfStore`, which doesn't buffer, so nothing is lost.
- **Known judgment calls:** footer label "For agents" (spec names the action; the label is shorter for the narrow footer — `.help` carries the full meaning). `swift run` in Tasks 2–3 only needs file writes at launch, no Fn/Accessibility; fallback to the signed build is noted.
