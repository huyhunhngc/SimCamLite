import AVFoundation
import CoreImage

final class MacCameraSource: NSObject, FrameSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    let deviceID: String
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.ifateam.simcamlite.maccamera")
    private let lock = NSLock()
    private var latest: CIImage?
    private var configured = false
    private(set) var deviceName: String

    init(device: AVCaptureDevice) {
        deviceID = device.uniqueID
        deviceName = device.localizedName
        super.init()
    }

    static var availableDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    var title: String { deviceName }

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            guard granted, let self else { return }
            self.queue.async { self.startSession() }
        }
    }

    func stop() {
        queue.async { self.session.stopRunning() }
    }

    func currentImage(at time: CFTimeInterval) -> CIImage? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    private func startSession() {
        if !configured {
            guard let device = AVCaptureDevice(uniqueID: deviceID),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            session.sessionPreset = .high
            if session.canAddInput(input) {
                session.addInput(input)
            }
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: queue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
            session.commitConfiguration()
            configured = true
        }
        if !session.isRunning {
            session.startRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        lock.lock()
        latest = image
        lock.unlock()
    }
}
