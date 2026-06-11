import Testing
import Foundation
@testable import SidekitCore

@MainActor
struct IdentityTests {

    private func makeSUT(seed: IdentityState = IdentityState()) -> (IdentityStore, FakeIdentityPersistence) {
        let persistence = FakeIdentityPersistence(seed)
        return (IdentityStore(persistence: persistence), persistence)
    }

    // MARK: - EmailCheck

    @Test func plausibleEmailsPass() {
        #expect(EmailCheck.isPlausible("a@b.co"))
        #expect(EmailCheck.isPlausible("  user.name+tag@sub.example.com  ")) // trimmed
    }

    @Test func implausibleEmailsFail() {
        #expect(!EmailCheck.isPlausible(""))
        #expect(!EmailCheck.isPlausible("plainaddress"))
        #expect(!EmailCheck.isPlausible("a@b"))            // no dot in domain
        #expect(!EmailCheck.isPlausible("@b.co"))          // empty local part
        #expect(!EmailCheck.isPlausible("a@.co"))          // empty domain label
        #expect(!EmailCheck.isPlausible("a@b."))           // empty trailing label
        #expect(!EmailCheck.isPlausible("a b@c.do"))       // inner whitespace
        #expect(!EmailCheck.isPlausible("a@@b.co"))        // two @
    }

    // MARK: - Soft-gate welcome rule (spec §2): show on launch 1; if skipped, once more at launch ≥5; never after.

    @Test func welcomeLifecycleAcrossLaunches() {
        let (store, _) = makeSUT()
        store.recordLaunch()                       // launch 1
        #expect(store.shouldShowWelcome)
        store.welcomeShown()                       // shown, user skipped
        #expect(!store.shouldShowWelcome)          // not again this session
        store.recordLaunch()                       // 2
        store.recordLaunch()                       // 3
        store.recordLaunch()                       // 4
        #expect(!store.shouldShowWelcome)
        store.recordLaunch()                       // 5 — the one re-ask
        #expect(store.shouldShowWelcome)
        store.welcomeShown()
        store.recordLaunch()                       // 6+ — never again
        #expect(!store.shouldShowWelcome)
    }

    @Test func welcomeNeverShowsOnceEmailIsSet() {
        let (store, _) = makeSUT()
        store.recordLaunch()
        #expect(store.setEmail("you@example.com"))
        #expect(!store.shouldShowWelcome)
        store.recordLaunch() // any later launch
        #expect(!store.shouldShowWelcome)
    }

    @Test func ruleSurvivesPersistenceRoundTrip() {
        let (first, persistence) = makeSUT()
        first.recordLaunch()        // 1
        first.welcomeShown()        // skipped
        // "Relaunch": a fresh store loads the saved state.
        let (second, _) = makeSUT(seed: persistence.stored)
        second.recordLaunch()       // 2
        #expect(!second.shouldShowWelcome)
    }

    // MARK: - setEmail / clearEmail

    @Test func setEmailTrimsLowercasesAndPersists() {
        let (store, persistence) = makeSUT()
        #expect(store.setEmail("  You@Example.COM "))
        #expect(store.state.email == "you@example.com")
        #expect(persistence.stored.email == "you@example.com")
    }

    @Test func setEmailRejectsImplausibleWithoutSaving() {
        let (store, persistence) = makeSUT()
        #expect(!store.setEmail("nope"))
        #expect(store.state.email == nil)
        #expect(persistence.saveCount == 0)
    }

    @Test func clearEmailRemovesAndPersists() {
        let (store, persistence) = makeSUT(seed: IdentityState(email: "a@b.co"))
        store.clearEmail()
        #expect(store.state.email == nil)
        #expect(persistence.stored.email == nil)
    }

    // MARK: - Codec

    @Test func codecRoundTrips() {
        let state = IdentityState(email: "a@b.co", launchCount: 7, welcomeAutoShows: 2)
        #expect(IdentityCodec.decode(IdentityCodec.encode(state)) == state)
    }

    @Test func codecToleratesCorruptData() {
        #expect(IdentityCodec.decode(Data("not json".utf8)) == IdentityState())
        #expect(IdentityCodec.decode(Data()) == IdentityState())
    }
}
