import AppKit

@MainActor
final class SimulatorModel: ObservableObject {
    @Published private(set) var devices: [SimulatorDevice] = []
    @Published var selectedUDID: String? {
        didSet {
            guard oldValue != selectedUDID, let udid = selectedUDID else { return }
            Task { await loadApps(for: udid) }
        }
    }
    @Published private(set) var injectionStates: [String: Bool] = [:]
    @Published private(set) var appsByDevice: [String: [SimulatorApp]] = [:]
    @Published private(set) var toolsAvailable: Bool?
    @Published private(set) var isBusy = false
    @Published var message: String?
    private var isRefreshing = false

    var selectedDevice: SimulatorDevice? { devices.first { $0.udid == selectedUDID } }
    var apps: [SimulatorApp] { selectedUDID.flatMap { appsByDevice[$0] } ?? [] }
    var injectionEnabled: Bool { selectedUDID.flatMap { injectionStates[$0] } ?? false }
    var xcodeEnvironment: String { "\(SimulatorManager.injectVariable)=\(InjectInstaller.loaderPath)" }

    func isInjectionEnabled(_ udid: String) -> Bool { injectionStates[udid] ?? false }
    func apps(for udid: String) -> [SimulatorApp] { appsByDevice[udid] ?? [] }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let booted = try await SimulatorManager.bootedDevices()
            toolsAvailable = true
            var states: [String: Bool] = [:]
            for device in booted {
                states[device.udid] = await SimulatorManager.isInjectionEnabled(on: device.udid)
            }
            devices = booted
            injectionStates = states
            appsByDevice = appsByDevice.filter { states[$0.key] != nil }
            if selectedUDID == nil || !booted.contains(where: { $0.udid == selectedUDID }) {
                selectedUDID = booted.first?.udid
            }
            message = booted.isEmpty ? "No booted simulator" : nil
            for device in booted {
                await loadApps(for: device.udid)
            }
        } catch {
            toolsAvailable = false
            devices = []
            message = error.localizedDescription
        }
    }

    func setInjection(_ enabled: Bool, udid: String? = nil) async {
        guard let udid = udid ?? selectedUDID else { return }
        await perform {
            try await SimulatorManager.setInjectionEnabled(enabled, on: udid)
            self.injectionStates[udid] = await SimulatorManager.isInjectionEnabled(on: udid)
            self.message = enabled ? "Injection enabled. Apps launched from now on use SimCamLite." : "Injection disabled."
        }
    }

    func launch(_ app: SimulatorApp, udid: String? = nil) async {
        guard let udid = udid ?? selectedUDID else { return }
        await perform {
            try await SimulatorManager.launch(app.bundleID, on: udid)
            self.message = "Launched \(app.name) with SimCamLite"
        }
    }

    func copyXcodeEnvironment() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(xcodeEnvironment, forType: .string)
        message = "Copied \(xcodeEnvironment)"
    }

    func openSimulatorApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iphonesimulator") else {
            message = "Simulator.app not found. Install Xcode first."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func loadApps(for udid: String) async {
        if let apps = try? await SimulatorManager.userApps(on: udid) {
            appsByDevice[udid] = apps
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            message = error.localizedDescription
        }
    }
}
