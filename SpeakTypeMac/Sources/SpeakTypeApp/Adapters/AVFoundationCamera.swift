// @preconcurrency: AVFoundation's capture types predate strict concurrency and aren't
// Sendable; the serial session queue + lock pattern (mirroring AVAudioCapture) keeps all
// configuration/start/stop on one thread, so the class is @unchecked Sendable.
@preconcurrency import AVFoundation
import SpeakTypeCore

/// Front-camera self-view via `AVCaptureSession`. Discovers built-in/external/Continuity
/// cameras, opens one as the session input, and feeds a mirrored `previewLayer` the Mirror
/// view hosts. All session work runs on a private serial queue (startRunning blocks, so it
/// must never touch the main thread); the lock guards `isRunning`/config races — hence
/// `@unchecked Sendable`. The preview layer is intentionally outside the `CameraPort`
/// contract (rendering is an app-side concern).
final class AVFoundationCamera: CameraPort, @unchecked Sendable {
    private let session = AVCaptureSession()
    let previewLayer: AVCaptureVideoPreviewLayer
    private let queue = DispatchQueue(label: "com.speaktype.camera.session")
    private let lock = NSLock()

    init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
    }

    func availableDevices() -> [CameraDevice] {
        discoveredDevices().map { CameraDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    /// An additional mirrored preview layer on the **same session**, for the full-screen overlay to
    /// host (a single `AVCaptureVideoPreviewLayer` can live in only one view hierarchy, so the overlay
    /// can't reuse `previewLayer`). AVFoundation supports multiple preview layers per session, so this
    /// opens **no second camera / green light**. Mirroring is set on the layer's own connection, which
    /// exists immediately because the overlay is only ever entered from an already-running preview.
    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return layer
    }

    func start(deviceID: String?) {
        queue.async { [self] in
            let device = resolveDevice(deviceID)
            guard let device else {
                Diag.log("camera.start: no device resolved (deviceID=\(deviceID ?? "nil"))")
                return
            }
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if session.canAddInput(input) { session.addInput(input) }
            } catch {
                session.commitConfiguration()
                Diag.log("camera.start: input FAILED: \(error)")
                return
            }
            session.commitConfiguration()

            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }

            lock.lock()
            session.startRunning()
            lock.unlock()
            Diag.log("camera.start: running device=\(device.localizedName)")
        }
    }

    func stop() {
        queue.async { [self] in
            lock.lock()
            session.stopRunning()
            lock.unlock()
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            session.commitConfiguration()
            Diag.log("camera.stop")
        }
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return session.isRunning
    }

    private func resolveDevice(_ deviceID: String?) -> AVCaptureDevice? {
        if let deviceID, !deviceID.isEmpty,
           let match = discoveredDevices().first(where: { $0.uniqueID == deviceID }) {
            return match
        }
        return AVCaptureDevice.default(for: .video)
    }

    /// The video devices we offer as Mirror sources: built-in, external webcams, and
    /// Continuity Camera. Used by both device listing and id resolution.
    private func discoveredDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
}
