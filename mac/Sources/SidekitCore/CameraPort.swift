import Foundation

// The pure camera control port for the Mirror's live self-view. Like `AudioCapturing`
// keeps AVAudioEngine out of the core, this keeps AVCaptureDevice/AVCaptureSession out
// of it: the Mirror's UI and lifecycle depend only on this protocol and value type, so a
// FakeCamera can stand in for device-driven tests. The live preview layer
// (AVCaptureVideoPreviewLayer) is deliberately NOT here — rendering frames is a concrete
// app-side concern, exposed only on the AVFoundation adapter the Mirror view hosts.

/// A selectable camera, identified by the adapter's `AVCaptureDevice.uniqueID` (mapped to
/// `id`) with a human-readable `name` (`localizedName`). Pure value type — no system types.
public struct CameraDevice: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// Camera control surface the Mirror depends on. `start(deviceID:)` opens capture (nil =
/// system default / built-in camera); `stop()` ends it; `isRunning` reports the live state.
/// The concrete adapter additionally owns the preview layer, which is outside this contract.
public protocol CameraPort: AnyObject {
    var isRunning: Bool { get }
    func availableDevices() -> [CameraDevice]
    func start(deviceID: String?)
    func stop()
}
