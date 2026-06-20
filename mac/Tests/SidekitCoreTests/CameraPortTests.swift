import Testing
@testable import SidekitCore

// Pins the CameraPort contract against the FakeCamera test double: starting runs the
// camera and records the requested device, stopping turns it off, counts track each
// call, and availableDevices() reflects the configured list. Proves a fake can stand
// in for the real AVFoundation adapter in Mirror lifecycle tests.
@Suite struct CameraPortTests {
    @Test func startsRunningAndRecordsDevice() {
        let cam = FakeCamera()
        #expect(cam.isRunning == false)
        cam.start(deviceID: "cam-42")
        #expect(cam.isRunning == true)
        #expect(cam.lastStartedDeviceID == "cam-42")
    }

    @Test func stopTurnsItOff() {
        let cam = FakeCamera()
        cam.start(deviceID: "cam-42")
        cam.stop()
        #expect(cam.isRunning == false)
    }

    @Test func startAndStopCountsIncrement() {
        let cam = FakeCamera()
        cam.start(deviceID: nil)
        cam.start(deviceID: "cam-1")
        cam.stop()
        #expect(cam.startCount == 2)
        #expect(cam.stopCount == 1)
    }

    @Test func availableDevicesReturnsConfiguredList() {
        let cam = FakeCamera()
        cam.devices = [
            CameraDevice(id: "a", name: "FaceTime HD"),
            CameraDevice(id: "b", name: "External Webcam"),
        ]
        #expect(cam.availableDevices() == cam.devices)
    }

    @Test func defaultStartRecordsNilDevice() {
        let cam = FakeCamera()
        cam.start(deviceID: nil)
        #expect(cam.lastStartedDeviceID == nil)
        #expect(cam.isRunning == true)
    }
}
