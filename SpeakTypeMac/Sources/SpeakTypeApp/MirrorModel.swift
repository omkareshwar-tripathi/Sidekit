import AVFoundation
import SpeakTypeCore

/// `@MainActor ObservableObject` that owns the Mirror's state, its camera, and the camera
/// permission gate. The single invariant — **camera runs iff the Mirror is open** (not
/// collapsed) — is enforced by routing every state transition through `syncCamera()`, which
/// starts capture for `small`/`expanded` and stops it for `collapsed`. Permission is requested
/// lazily on the first `tap()`; a denial flips `permissionDenied` so the view can offer an
/// "Open Settings" prompt instead of a dead preview.
///
/// NOTE: wiring `dismiss()` to panel-close / app-deactivate (so the Mirror collapses and the
/// camera stops when the Shelf hides) is the next brick (MIRROR-LIFECYCLE) — not handled here.
@MainActor
final class MirrorModel: ObservableObject {
    @Published private(set) var state: MirrorState = .collapsed
    @Published private(set) var permissionDenied = false
    @Published private(set) var devices: [CameraDevice] = []
    /// nil = system default camera; a non-nil id selects a specific discovered device.
    @Published var selectedDeviceID: String?
    /// Manual "edge light" — a bright-white inset frame that acts as a fill light in dim rooms. A
    /// session preference (no frame sampling — privacy-clean): it carries across small/expanded/full
    /// screen while the Mirror stays open and resets to off on `dismiss()` (fresh each open).
    @Published private(set) var edgeLightOn = false

    /// Held concretely (not as `CameraPort`) so the view can read `previewLayer`; controlled
    /// through the `CameraPort` surface for start/stop.
    let camera = AVFoundationCamera()
    var previewLayer: AVCaptureVideoPreviewLayer { camera.previewLayer }

    /// The full-display overlay window, created lazily on the first full-screen entry (no overlay
    /// window exists until then) and driven by `state == .fullScreen` via `syncOverlay()`.
    private var overlay: MirrorOverlayPanel?

    /// Primary tap on the Mirror: advance size, requesting camera permission the first time.
    func tap() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            advance()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted { self.advance() } else { self.permissionDenied = true }
                }
            }
        default: // .denied, .restricted
            permissionDenied = true
        }
    }

    /// Move to the next size and bring the camera in line with the new state.
    private func advance() {
        permissionDenied = false
        state = state.tapped()
        syncCamera()
    }

    /// Collapse the Mirror back to its button (camera off).
    func dismiss() {
        // Clear any stale denial so re-opening re-queries authorization fresh — granting access in
        // System Settings then reopening recovers without an app restart (the MIRROR-LIFECYCLE
        // deactivate-dismiss fires when the user opens System Settings).
        permissionDenied = false
        edgeLightOn = false   // edge light is fresh each open (spec decision #5)
        state = state.dismissed()
        syncCamera()
        syncOverlay()
    }

    /// Flip the manual edge light on/off (the ☀ toggle, in both the windowed strip and the overlay).
    func toggleEdgeLight() {
        edgeLightOn.toggle()
    }

    /// Toggle the full-display overlay: an open windowed preview goes full screen, the overlay exits
    /// back to `.expanded`. Guarded on the Mirror being open so it can never enter full screen (and
    /// start the camera) straight from `.collapsed`, bypassing the permission gate — the full-screen
    /// control only exists in the open preview / the overlay, so this just hardens the invariant.
    /// No `syncCamera()`: both sides of this toggle keep the camera running (openness is unchanged),
    /// so the session is left alone — the overlay rides on a fresh preview layer of the same session,
    /// avoiding a needless capture restart / green-light flicker on every toggle.
    func toggleFullScreen() {
        guard state.cameraShouldRun else { return }
        state = state.toggledFullScreen()
        syncOverlay()
    }

    /// Switch the active source; restart capture immediately if the Mirror is open.
    func selectDevice(_ id: String?) {
        selectedDeviceID = id
        if state.cameraShouldRun {
            camera.stop()
            camera.start(deviceID: id)
        }
    }

    /// Enforce the invariant: capture runs (refreshing the device list) iff the Mirror is open.
    private func syncCamera() {
        if state.cameraShouldRun {
            devices = camera.availableDevices()
            camera.start(deviceID: selectedDeviceID)
        } else {
            camera.stop()
        }
    }

    /// Bind the overlay window to `state == .fullScreen`: show it (creating it the first time) with a
    /// fresh mirrored preview layer, or hide it. Exit (✕ / click / Esc) routes back through
    /// `toggleFullScreen()` → `.expanded`. Hiding only touches an already-created overlay, so a normal
    /// collapse never instantiates a window that was never used.
    private func syncOverlay() {
        if state == .fullScreen {
            let overlay = overlay ?? MirrorOverlayPanel()
            self.overlay = overlay
            overlay.show(previewLayer: camera.makePreviewLayer(), model: self) { [weak self] in
                self?.toggleFullScreen()
            }
        } else {
            overlay?.hide()
        }
    }
}
