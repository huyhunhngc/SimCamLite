import AppKit
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
}

@MainActor
final class AppModel: ObservableObject {
    let back = StreamController(label: "Back")
    let front = StreamController(label: "Front")
    @Published var frontFollowsBack = true { didSet { syncPipeline() } }
    @Published var deviceProfile: DeviceProfile = .triple { didSet { syncPipeline() } }
    @Published private(set) var backPreview: CGImage?
    @Published private(set) var frontPreview: CGImage?
    @Published private(set) var clients: [ConnectedClient] = []
    @Published private(set) var sharedMemoryReady = false
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
                self?.backPreview = backImage
                self?.frontPreview = frontImage
            }
        }
        pipeline.onClients = { [weak self] clients in
            MainActor.assumeIsolated { self?.receive(clients) }
        }
    }

    func start() {
        installInject()
        sharedMemoryReady = scl_host_open()
        back.source.start()
        front.source.start()
        syncPipeline()
        pipeline.start()
        Task { await simulators.refresh() }
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
        pipeline.stop()
        back.source.stop()
        front.source.stop()
    }

    private func syncPipeline() {
        let backSource = back.source
        let frontSource = front.source
        let backOptions = back.options
        let frontOptions = front.options
        let follows = frontFollowsBack
        let profile = deviceProfile.rawValue
        pipeline.update { config in
            config.backSource = backSource
            config.frontSource = frontSource
            config.backOptions = backOptions
            config.frontOptions = frontOptions
            config.frontFollowsBack = follows
            config.deviceProfile = profile
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

    private func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}

