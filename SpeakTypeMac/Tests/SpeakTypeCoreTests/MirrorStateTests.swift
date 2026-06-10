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

    @Test func cameraIsOnWhenFullScreen() {
        #expect(MirrorState.fullScreen.cameraShouldRun == true)
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

    @Test func tappedFromFullScreenReturnsToExpanded() {
        #expect(MirrorState.fullScreen.tapped() == .expanded)
    }

    // MARK: - toggledFullScreen() — enter full screen from any open/closed state, exit back to expanded

    @Test(arguments: [MirrorState.collapsed, .small, .expanded])
    func toggledFullScreenEntersFullScreen(from state: MirrorState) {
        #expect(state.toggledFullScreen() == .fullScreen)
    }

    @Test func toggledFullScreenFromFullScreenReturnsToExpanded() {
        #expect(MirrorState.fullScreen.toggledFullScreen() == .expanded)
    }

    @Test func toggledFullScreenRoundTrips() {
        #expect(MirrorState.expanded.toggledFullScreen().toggledFullScreen() == .expanded)
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

    @Test func dismissedFromFullScreenCollapses() {
        #expect(MirrorState.fullScreen.dismissed() == .collapsed)
    }

    // MARK: - invariant: dismissing always turns the camera off, from any state

    @Test(arguments: [MirrorState.collapsed, .small, .expanded, .fullScreen])
    func dismissedAlwaysStopsCamera(from state: MirrorState) {
        #expect(state.dismissed().cameraShouldRun == false)
    }
}
