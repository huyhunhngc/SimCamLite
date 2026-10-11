import AppKit
import AVFoundation
import Combine

enum DeviceProfile: UInt32, CaseIterable, Identifiable {
    case triple = 0
    case dualWide = 1
    case single = 2

    var id: UInt32 { rawValue }

    var title: String {
        switch self {
        case .triple: "Triple (0.5x · 1x · 3x)"
        case .dualWide: "Dual Wide (0.5x · 1x)"
        case .single: "Single wide"
        }
    }

    /// Fits the toolbar; the menu shows `title`.
    var shortTitle: String {
        switch self {
        case .triple: "Triple"
        case .dualWide: "Dual Wide"
        case .single: "Single"
        }
    }
}

enum FrameRate: Int, CaseIterable, Identifiable {
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var title: String { "\(rawValue) fps" }
}

/// Kept separate from AppModel so per-frame preview updates only redraw the preview images.
@MainActor
final class PreviewFeed: ObservableObject {
    @Published fileprivate(set) var image: CGImage?
}

@MainActor
final class AppModel: ObservableObject {
    let back = StreamController(label: "Back")
    let front = StreamController(label: "Front")
    @Published var frontFollowsBack = true { didSet { syncPipeline() } }
    @Published var deviceProfile: DeviceProfile = .triple { didSet { syncPipeline() } }
    @Published var frameRate: FrameRate = .fps30 { didSet { syncPipeline() } }
    let backPreview = PreviewFeed()
    let frontPreview = PreviewFeed()
    @Published private(set) var clients: [ConnectedClient] = []
    @Published private(set) var sharedMemoryReady = false
    @Published private(set) var isStreaming = false
    @Published private(set) var injectInstalled = false
    @Published var installError: String?
    @Published var toast: String?

    let simulators = SimulatorModel()
    let permissions = PermissionsModel()
    var onShowPermissions: (() -> Void)?
    private let pipeline = RenderPipeline()
    private var photoCounts: [Int32: UInt64] = [:]
    private var cancellables: Set<AnyCancellable> = []

    init() {
        for stream in [back, front] {
            stream.onChange = { [weak self] in self?.syncPipeline() }
            stream.onCameraPermissionNeeded = { [weak self] in self?.onShowPermissions?() }
            stream.permissions = permissions
        }
        back.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        front.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        simulators.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)
        permissions.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &cancellables)

        pipeline.onPreview = { [weak self] backImage, frontImage in
            MainActor.assumeIsolated {
                self?.backPreview.image = backImage
                self?.frontPreview.image = frontImage
            }
        }
        pipeline.onClients = { [weak self] clients in
            MainActor.assumeIsolated { self?.receive(clients) }
        }
    }

    func start() {
        installInject()
        sharedMemoryReady = scl_host_open()
        restoreSettings()
        startStreaming()
        Task { await simulators.refresh() }
        simulators.startMonitoring()
        objectWillChange
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.saveSettings() }
            .store(in: &cancellables)
    }

    private func restoreSettings() {
        guard let settings = AppSettings.load() else { return }
        frameRate = FrameRate(rawValue: settings.frameRate) ?? .fps30
        deviceProfile = DeviceProfile(name: settings.deviceProfile) ?? .triple
        frontFollowsBack = settings.frontFollowsBack
        for (stream, saved) in [(back, settings.back), (front, settings.front)] {
            stream.options = saved.options
            if case .camera = saved.source, AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
                continue // never prompt for camera access at launch
            }
            if saved.source != .pattern { stream.use(saved.source) }
        }
        simulators.preferredUDID = settings.selectedUDID
    }

    func saveSettings() {
        AppSettings(
            frameRate: frameRate.rawValue,
            deviceProfile: deviceProfile.name,
            frontFollowsBack: frontFollowsBack,
            back: .init(source: back.spec, options: back.options),
            front: .init(source: front.spec, options: front.options),
            selectedUDID: simulators.selectedUDID ?? simulators.preferredUDID
        ).save()
    }

    func startStreaming() {
        guard !isStreaming else { return }
        if !sharedMemoryReady {
            sharedMemoryReady = scl_host_open()
        }
        back.activate()
        front.activate()
        syncPipeline()
        pipeline.start()
        isStreaming = true
    }

    /// Stops rendering; the heartbeat goes stale so iOS apps show "Host app is not running".
    func stopStreaming() {
        guard isStreaming else { return }
        pipeline.stop()
        back.deactivate()
        front.deactivate()
        isStreaming = false
    }

    func installInject() {
        do {
            injectInstalled = try InjectInstaller.install() || InjectInstaller.isInstalled
            installError = nil
        } catch {
            injectInstalled = InjectInstaller.isInstalled
            installError = error.localizedDescription
        }
    }

    var frontSeparate: Bool {
        get { !frontFollowsBack }
        set { frontFollowsBack = !newValue }
    }

    func stop() {
        saveSettings()
        stopStreaming()
    }

    private func syncPipeline() {
        let backSource = back.source
        let frontSource = front.source
        let backOptions = back.options
        let frontOptions = front.options
        let follows = frontFollowsBack
        let profile = deviceProfile.rawValue
        let rate = Double(frameRate.rawValue)
        pipeline.update { config in
            config.backSource = backSource
            config.frontSource = frontSource
            config.backOptions = backOptions
            config.frontOptions = frontOptions
            config.frontFollowsBack = follows
            config.deviceProfile = profile
            config.frameRate = rate
        }
    }

    private func receive(_ newClients: [ConnectedClient]) {
        for client in newClients {
            if let previous = photoCounts[client.pid], client.photoCount > previous {
                showToast("📸 \(client.processName) captured a photo")
            }
            photoCounts[client.pid] = client.photoCount
        }
        if newClients != clients {
            clients = newClients
        }
    }

    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}

