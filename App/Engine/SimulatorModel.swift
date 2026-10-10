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
    @Published private(set) var injectsAllSimulators = InjectionPreferences.injectsAllSimulators
    private var isRefreshing = false
    private var monitor: Task<Void, Never>?
    /// Booted simulators whose injection was already restored; a device leaving this set and booting again is re-checked.
    private var restoredUDIDs: Set<String> = []

    var selectedDevice: SimulatorDevice? { devices.first { $0.udid == selectedUDID } }
    var apps: [SimulatorApp] { selectedUDID.flatMap { appsByDevice[$0] } ?? [] }
    var injectionEnabled: Bool { selectedUDID.flatMap { injectionStates[$0] } ?? false }
    var xcodeEnvironment: String { "\(SimulatorManager.injectVariable)=\(InjectInstaller.loaderPath)" }

    func isInjectionEnabled(_ udid: String) -> Bool { injectionStates[udid] ?? false }
    func isInjectionRemembered(_ udid: String) -> Bool { injectsAllSimulators || InjectionPreferences.isRemembered(udid) }
    func apps(for udid: String) -> [SimulatorApp] { appsByDevice[udid] ?? [] }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let booted = try await SimulatorManager.bootedDevices()
            toolsAvailable = true
            injectsAllSimulators = InjectionPreferences.injectsAllSimulators
            var states: [String: Bool] = [:]
            for device in booted {
                states[device.udid] = await restoreInjection(on: device.udid)
            }
            restoredUDIDs.formIntersection(states.keys)
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

    /// Watches for simulators booting or shutting down so remembered injection is restored without user action.
    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                await self?.poll()
            }
        }
    }

    /// Enables injection and remembers it, so it is restored after the simulator restarts.
    func setInjection(_ enabled: Bool, udid: String? = nil) async {
        guard let udid = udid ?? selectedUDID else { return }
        InjectionPreferences.remember(enabled, udid: udid)
        await perform {
            try await SimulatorManager.setInjectionEnabled(enabled, on: udid)
            self.injectionStates[udid] = await SimulatorManager.isInjectionEnabled(on: udid)
            self.message = enabled
                ? "Injection enabled. Apps launched from now on use SimCamLite, also after the simulator restarts."
                : "Injection disabled."
        }
    }

    func setInjectsAllSimulators(_ enabled: Bool) async {
        InjectionPreferences.injectsAllSimulators = enabled
        injectsAllSimulators = enabled
        restoredUDIDs.removeAll()
        await refresh()
        if enabled, InjectInstaller.isInstalled {
            message = "Injection is enabled on every simulator as it boots."
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

    /// Cheap check (one `simctl list`) that refreshes only when the set of booted simulators changed.
    private func poll() async {
        guard !isRefreshing, let booted = try? await SimulatorManager.bootedDevices() else { return }
        let udids = Set(booted.map(\.udid))
        if udids != Set(devices.map(\.udid)) || !udids.isSubset(of: restoredUDIDs)
            || InjectionPreferences.injectsAllSimulators != injectsAllSimulators {
            await refresh()
        }
    }

    /// Re-applies remembered injection the first time a booted simulator is seen; returns the current state.
    private func restoreInjection(on udid: String) async -> Bool {
        let enabled = await SimulatorManager.isInjectionEnabled(on: udid)
        guard !enabled, !restoredUDIDs.contains(udid) else {
            restoredUDIDs.insert(udid)
            return enabled
        }
        guard InjectionPreferences.shouldInject(udid), InjectInstaller.isInstalled else {
            restoredUDIDs.insert(udid)
            return false
        }
        // Left out of restoredUDIDs on failure (e.g. still booting) so the next refresh retries.
        guard (try? await SimulatorManager.setInjectionEnabled(true, on: udid)) != nil else { return false }
        let restored = await SimulatorManager.isInjectionEnabled(on: udid)
        if restored { restoredUDIDs.insert(udid) }
        return restored
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
