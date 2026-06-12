import Foundation
import Testing
@testable import SidekitCore

// MARK: - Fakes

private final class FakeEngine: TextGenerating, @unchecked Sendable {
    var loads = 0, unloads = 0
    var generated: [(system: String, user: String, temperature: Float)] = []
    var loadError: Error?
    var reply = "REPLY"
    var generateError: Error?

    func load() async throws { loads += 1; if let loadError { throw loadError } }
    func unload() async { unloads += 1 }
    func generate(system: String, user: String, temperature: Float) async throws -> String {
        generated.append((system, user, temperature))
        if let generateError { throw generateError }
        try Task.checkCancellation()
        return reply
    }
}

private final class FakeProvisioner: ModelProvisioning, @unchecked Sendable {
    var isDownloaded: Bool
    var downloadError: Error?
    var progressTicks: [Double] = [0.5]
    init(downloaded: Bool) { isDownloaded = downloaded }
    func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        for tick in progressTicks {
            progress(tick)
            await Task.yield() // let the session's main-actor progress hop land before we finish
        }
        if let downloadError { throw downloadError }
        isDownloaded = true
    }
    func remove() throws { isDownloaded = false }
}

private final class FakeIdleTimer: IntelligenceIdleTimer {
    var pending: (() -> Void)?
    var cancels = 0
    func start(after seconds: Double, _ fire: @escaping @Sendable () -> Void) { pending = fire }
    func cancel() { cancels += 1; pending = nil }
    func fire() { pending?(); pending = nil }
}

private struct TestError: Error {}

// MARK: - Tests

@MainActor
struct IntelligenceSessionTests {
    final class Recorder {
        var states: [IntelligenceSession.State] = []
        var results: [String] = []
        var errors: [String] = []
    }

    private struct Rig {
        let session: IntelligenceSession
        let polish: FakeEngine
        let draft: FakeEngine
        let provisioner: FakeProvisioner
        let idle: FakeIdleTimer
        let rec: Recorder
    }

    private func make(downloaded: Bool = true) -> Rig {
        let polish = FakeEngine()
        let draft = FakeEngine()
        let provisioner = FakeProvisioner(downloaded: downloaded)
        let idle = FakeIdleTimer()
        let session = IntelligenceSession(polishEngine: polish, draftEngine: draft,
                                          provisioner: provisioner, idle: idle)
        let rec = Recorder()
        session.onStateChanged = { rec.states.append($0) }
        session.onResult = { rec.results.append($0) }
        session.onError = { rec.errors.append($0) }
        return Rig(session: session, polish: polish, draft: draft,
                   provisioner: provisioner, idle: idle, rec: rec)
    }

    @Test func initialStateReflectsDownload() {
        #expect(make(downloaded: true).session.state == .ready)
        #expect(make(downloaded: false).session.state == .needsModel)
    }

    @Test func downloadHappyPathReportsProgressThenReady() async {
        let rig = make(downloaded: false)
        await rig.session.requestDownload()?.value
        #expect(rig.rec.states.contains(.downloading(0.0)))
        #expect(rig.rec.states.contains(.downloading(0.5)))
        #expect(rig.session.state == .ready)
    }

    @Test func downloadFailureStaysNeedsModelWithError() async {
        let rig = make(downloaded: false)
        rig.provisioner.downloadError = TestError()
        await rig.session.requestDownload()?.value
        #expect(rig.session.state == .needsModel)
        #expect(rig.rec.errors == ["Download interrupted — Retry"])
    }

    @Test func downloadOfflineShowsTheOfflineMessage() async {
        let rig = make(downloaded: false)
        rig.provisioner.downloadError = URLError(.notConnectedToInternet)
        await rig.session.requestDownload()?.value
        #expect(rig.session.state == .needsModel)
        #expect(rig.rec.errors == ["You're offline — the one-time model download needs internet."])
    }

    @Test func draftChipRunsOnTheDraftEngineOnly() async {
        let rig = make()
        rig.draft.reply = "```\nHello.\n```"
        await rig.session.run(chip: .draftEmail, tone: .professional, input: " notes ")?.value
        #expect(rig.draft.loads == 1)
        #expect(rig.polish.loads == 0 && rig.polish.generated.isEmpty)
        #expect(rig.draft.generated.count == 1)
        #expect(rig.draft.generated[0].user == "notes") // trimmed by the input check
        #expect(rig.draft.generated[0].temperature == 0.0)
        #expect(rig.draft.generated[0].system ==
                IntelligencePrompt.build(chip: .draftEmail, tone: .professional).system)
        #expect(rig.rec.results == ["Hello."]) // sanitized
        #expect(rig.session.state == .warm)
        #expect(rig.rec.states.contains(.loading) && rig.rec.states.contains(.generating))
    }

    @Test func polishChipRunsOnThePolishEngineOnly() async {
        let rig = make()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        #expect(rig.polish.loads == 1 && rig.polish.generated.count == 1)
        #expect(rig.draft.loads == 0 && rig.draft.generated.isEmpty)
        #expect(rig.polish.generated[0].temperature == 0.0)
        #expect(rig.polish.generated[0].user == "---\nTranscript:\nx") // lab-exact framing
    }

    @Test func sameRoleTwiceSkipsReloadAndResetsIdleTimer() async {
        let rig = make()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        await rig.session.run(chip: .polish, tone: .friendly, input: "y")?.value
        #expect(rig.polish.loads == 1)
        #expect(rig.idle.cancels >= 1)      // a new run cancels the pending unload
        #expect(rig.idle.pending != nil)    // …and re-arms it after finishing
    }

    @Test func roleSwitchUnloadsTheWarmModelFirst() async {
        let rig = make()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        await rig.session.run(chip: .draftEmail, tone: .keepTone, input: "y")?.value
        #expect(rig.polish.unloads == 1)    // Gemma left before Qwen arrived
        #expect(rig.draft.loads == 1)
        #expect(rig.session.state == .warm)
    }

    @Test func emptyInputDoesNothingAndTooLongErrorsWithoutEngineCalls() async {
        let rig = make()
        await rig.session.run(chip: .summarize, tone: .keepTone, input: "   ")?.value
        #expect(rig.draft.generated.isEmpty && rig.rec.errors.isEmpty)
        await rig.session.run(chip: .summarize, tone: .keepTone,
                              input: String(repeating: "a", count: 6001))?.value
        #expect(rig.draft.generated.isEmpty)
        #expect(rig.rec.errors == [IntelligencePrompt.tooLongMessage])
        #expect(rig.session.state == .ready)
    }

    @Test func emptySanitizedOutputIsAnHonestError() async {
        let rig = make()
        rig.draft.reply = "  \n "
        await rig.session.run(chip: .draftMessage, tone: .keepTone, input: "x")?.value
        #expect(rig.rec.errors == ["Couldn't draft that — try again."])
        #expect(rig.rec.results.isEmpty)
        #expect(rig.session.state == .warm) // model stays warm; the input is preserved UI-side
    }

    @Test func loadFailureReturnsToReadyWithDamageMessage() async {
        let rig = make()
        rig.polish.loadError = TestError()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        #expect(rig.session.state == .ready)
        #expect(rig.rec.errors == ["Model files look damaged — download again."])
    }

    @Test func generationFailureStaysWarmWithRetryMessage() async {
        let rig = make()
        rig.polish.generateError = TestError()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        #expect(rig.session.state == .warm)
        #expect(rig.rec.errors == ["Couldn't draft that — try again."])
    }

    @Test func idleTimerFireUnloadsBackToReady() async {
        let rig = make()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        rig.idle.fire()
        await rig.session.settle()
        #expect(rig.polish.unloads == 1)
        #expect(rig.session.state == .ready)
    }

    @Test func cancelDuringGenerationReturnsWarmSilently() async {
        let rig = make()
        rig.polish.generateError = CancellationError()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        #expect(rig.session.state == .warm)
        #expect(rig.rec.errors.isEmpty && rig.rec.results.isEmpty)
    }

    @Test func memoryPressureWhenWarmUnloadsImmediately() async {
        let rig = make()
        await rig.session.run(chip: .draftEmail, tone: .keepTone, input: "x")?.value
        rig.session.memoryPressure()
        await rig.session.settle()
        #expect(rig.draft.unloads == 1)
        #expect(rig.session.state == .ready)
    }

    @Test func modelRemovedDropsToNeedsModel() async {
        let rig = make()
        await rig.session.run(chip: .polish, tone: .keepTone, input: "x")?.value
        try? rig.provisioner.remove()
        rig.session.modelRemoved()
        await rig.session.settle()
        #expect(rig.polish.unloads == 1)
        #expect(rig.session.state == .needsModel)
    }

    /// When both engine slots point to the SAME object (shared Qwen2.5), a role switch
    /// must relabel warmRole without unloading. The engine loads exactly once and zero unloads.
    @Test func sharedEngineRoleSwitchRelabelsWithoutUnload() async {
        let shared = FakeEngine()
        let provisioner = FakeProvisioner(downloaded: true)
        let idle = FakeIdleTimer()
        let session = IntelligenceSession(polishEngine: shared, draftEngine: shared,
                                          provisioner: provisioner, idle: idle)
        let rec = Recorder()
        session.onStateChanged = { rec.states.append($0) }
        session.onResult    = { rec.results.append($0) }
        session.onError     = { rec.errors.append($0) }

        // Warm up the polish role.
        await session.run(chip: .polish, tone: .keepTone, input: "hello")?.value
        #expect(shared.loads == 1)

        // Switch to draft role — shared engine must NOT be unloaded/reloaded.
        await session.run(chip: .draftEmail, tone: .professional, input: "world")?.value
        #expect(shared.loads == 1,  "engine loaded more than once — should relabel, not swap")
        #expect(shared.unloads == 0, "engine was unloaded on a role switch — should not be")
        #expect(rec.results.count == 2, "both runs should produce a result")

        // The session must never have gone through .loading a second time.
        let loadingCount = rec.states.filter { $0 == .loading }.count
        #expect(loadingCount == 1, "went through .loading \(loadingCount) times; expected exactly 1")
    }
}
