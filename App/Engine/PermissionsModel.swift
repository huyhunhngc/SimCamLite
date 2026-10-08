import AppKit
import AVFoundation

@MainActor
final class PermissionsModel: ObservableObject {
    @Published private(set) var camera = AVCaptureDevice.authorizationStatus(for: .video)
    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    var cameraGranted: Bool { camera == .authorized }
    var cameraBlocked: Bool { camera == .denied || camera == .restricted }

    func refresh() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status != camera {
            camera = status
        }
    }

    @discardableResult
    func requestCamera() async -> Bool {
        refresh()
        switch camera {
        case .authorized:
            return true
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            refresh()
            return granted
        default:
            openCameraSettings()
            return false
        }
    }

    func openCameraSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Camera")!
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open(url, configuration: configuration)
    }
}
