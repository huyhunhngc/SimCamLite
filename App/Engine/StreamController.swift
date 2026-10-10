import AVFoundation
import UniformTypeIdentifiers
import Combine

@MainActor
final class StreamController: ObservableObject {
    let label: String
    @Published private(set) var kind: SourceKind = .testPattern
    @Published private(set) var source: FrameSource
    @Published var options = RenderOptions() { didSet { onChange?() } }
    @Published var isPaused = false { didSet { applyPause() } }
    @Published var errorMessage: String?
    var onChange: (() -> Void)?
    var onCameraPermissionNeeded: (() -> Void)?
    weak var permissions: PermissionsModel?
    /// False while streaming is stopped: sources stay idle (Mac camera off) until `activate()`.
    private(set) var isActive = true

    init(label: String) {
        self.label = label
        source = TestPatternSource(label: label)
    }

    var videoSource: VideoSource? { source as? VideoSource }
    var cameraDeviceID: String? { (source as? MacCameraSource)?.deviceID }

    var fileURL: URL? {
        switch source {
        case let image as ImageSource: image.url
        case let video as VideoSource: video.url
        default: nil
        }
    }

    func useTestPattern() {
        replace(with: TestPatternSource(label: label), kind: .testPattern)
    }

    func useImage(_ url: URL) {
        let image = ImageSource(url: url)
        guard image.isValid else {
            errorMessage = "Cannot read image \(url.lastPathComponent)"
            return
        }
        RecentFiles.add(url)
        replace(with: image, kind: .image)
    }

    func useVideo(_ url: URL) {
        RecentFiles.add(url)
        replace(with: VideoSource(url: url), kind: .video)
    }

    func useCamera(_ device: AVCaptureDevice) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                permissions?.refresh()
                useCamera(device)
            }
            return
        }
        if status == .denied || status == .restricted {
            errorMessage = "Camera access is denied. Allow SimCamLite in System Settings › Privacy & Security › Camera."
            onCameraPermissionNeeded?()
            return
        }
        replace(with: MacCameraSource(device: device), kind: .macCamera)
    }

    func useFile(_ url: URL) {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            errorMessage = "Unsupported file \(url.lastPathComponent)"
            return
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            useVideo(url)
        } else if type.conforms(to: .image) {
            useImage(url)
        } else {
            errorMessage = "Unsupported file \(url.lastPathComponent)"
        }
    }

    private func replace(with newSource: FrameSource, kind: SourceKind) {
        source.stop()
        source = newSource
        self.kind = kind
        errorMessage = nil
        isPaused = false
        if isActive { newSource.start() }
        onChange?()
    }

    func activate() {
        isActive = true
        if !(isPaused && videoSource != nil) { source.start() }
    }

    func deactivate() {
        isActive = false
        source.stop()
    }

    private func applyPause() {
        guard isActive, let video = videoSource else { return }
        if isPaused {
            video.stop()
        } else {
            video.start()
        }
    }
}

