import Testing
@testable import SpeakTypeCore

struct MirrorStateTests {

    // MARK: - cameraShouldRun (the lifecycle invariant: camera runs iff Mirror is open)

    @Test func cameraIsOffWhenCollapsed() {
        #expect(MirrorState.collapsed.cameraShouldRun == false)
    }

    @Test func cameraIsOnWhenSmall() {
        #expect(MirrorState.small.cameraShouldRun == true)
    }

    @Test func cameraIsOnWhenExpanded() {
        #expect(MirrorState.expanded.cameraShouldRun == true)
    }

    // MARK: - tapped() — open from button, then toggle small ⇄ expanded, never collapse

    @Test func tappedFromCollapsedOpensSmall() {
        #expect(MirrorState.collapsed.tapped() == .small)
    }

    @Test func tappedFromSmallExpands() {
        #expect(MirrorState.small.tapped() == .expanded)
    }

    @Test func tappedFromExpandedShrinksToSmall() {
        #expect(MirrorState.expanded.tapped() == .small)
    }

    // MARK: - dismissed() — every exit path funnels to collapsed (idempotent)

    @Test func dismissedFromCollapsedStaysCollapsed() {
        #expect(MirrorState.collapsed.dismissed() == .collapsed)
    }

    @Test func dismissedFromSmallCollapses() {
        #expect(MirrorState.small.dismissed() == .collapsed)
    }

    @Test func dismissedFromExpandedCollapses() {
        #expect(MirrorState.expanded.dismissed() == .collapsed)
    }

    // MARK: - invariant: dismissing always turns the camera off, from any state

    @Test(arguments: [MirrorState.collapsed, .small, .expanded])
    func dismissedAlwaysStopsCamera(from state: MirrorState) {
        #expect(state.dismissed().cameraShouldRun == false)
    }
}
