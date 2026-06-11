/// The Mirror's four display states — modeled as a pure value type so the camera
/// lifecycle is unit-testable without ever touching a real capture device.
///
/// The Mirror is a live self-view that lives inside the Shelf panel. It has four
/// resting states: `collapsed` (just the Mirror button, camera OFF), `small`
/// (a small inline self-view, camera ON), `expanded` (a larger self-view, camera ON),
/// and `fullScreen` (a borderless full-display overlay, camera ON). The Shelf always
/// reopens in `collapsed` — there is no size memory.
///
/// The single invariant that matters: **the camera runs iff the Mirror is open**
/// (`cameraShouldRun`). Every transition (`tapped`, `toggledFullScreen`, `dismissed`)
/// preserves it, and the tests pin it down so a future UI wiring bug can't leave the
/// camera running with the view collapsed.
public enum MirrorState: Sendable, Equatable {
    case collapsed
    case small
    case expanded
    case fullScreen

    /// Whether the camera should be capturing right now. True for the open states
    /// (`small`, `expanded`, `fullScreen`) and false when `collapsed` — i.e. the camera
    /// runs iff the Mirror is open. This is the lifecycle invariant the feature is built around.
    public var cameraShouldRun: Bool {
        self != .collapsed
    }

    /// Primary tap on the Mirror affordance: opens from the button, then toggles size.
    /// `collapsed → small`, `small → expanded`, `expanded → small`. A tap from full screen
    /// returns to the windowed `expanded` view. Tapping never collapses — closing is
    /// `dismissed`'s job — so the Mirror, once open, stays open.
    public func tapped() -> MirrorState {
        switch self {
        case .collapsed: return .small
        case .small: return .expanded
        case .expanded: return .small
        case .fullScreen: return .expanded
        }
    }

    /// Toggle the full-display overlay: any non-full-screen state enters `fullScreen`,
    /// and `fullScreen` exits back to `expanded` (deterministic — no size memory). Round-trips.
    public func toggledFullScreen() -> MirrorState {
        self == .fullScreen ? .expanded : .fullScreen
    }

    /// Collapse the Mirror back to its button, turning the camera off. Every exit path —
    /// the collapse control, the Shelf panel closing, or the app deactivating — funnels
    /// here. Idempotent: dismissing an already-collapsed Mirror stays `collapsed`.
    public func dismissed() -> MirrorState {
        .collapsed
    }
}
