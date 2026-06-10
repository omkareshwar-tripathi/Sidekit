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

    /// Held concretely (not as `CameraPort`) so the view can read `previewLayer`; controlled
    /// through the `CameraPort` surface for start/stop.
    let camera = AVFoundationCamera()
    var previewLayer: AVCaptureVideoPreviewLayer { camera.previewLayer }

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
        state = state.dismissed()
        syncCamera()
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
}
