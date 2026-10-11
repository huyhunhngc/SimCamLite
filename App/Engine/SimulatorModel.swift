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
    /// Projects whose schemes load SimCamLite when run from Xcode.
    @Published private(set) var xcodeProjects = XcodeSchemeSetup.projects
    /// Saved selection, applied once that simulator is listed.
    var preferredUDID: String?
    private var isRefreshing = false
    private var monitor: Task<Void, Never>?
    /// Booted simulators whose injection was already restored; a device leaving this set and booting again is re-checked.
    private var restoredUDIDs: Set<String> = []

    var bootedDevices: [SimulatorDevice] { devices.filter(\.isBooted) }
    var selectedDevice: SimulatorDevice? { devices.first { $0.udid == selectedUDID } }
    var apps: [SimulatorApp] { selectedUDID.flatMap { appsByDevice[$0] } ?? [] }
    /// Live state for a running simulator; for a shut-down one, whether it is enabled when it boots.
    var injectionEnabled: Bool {
        guard let device = selectedDevice else { return false }
        return device.isBooted ? injectionStates[device.udid] ?? false : isInjectionRemembered(device.udid)
    }
    /// At least one project scheme loads SimCamLite when run from Xcode.
    var isXcodeSetUp: Bool { xcodeSchemes.values.contains { $0.contains(where: \.isEnabled) } }
    var xcodeEnvironment: String { "\(SimulatorManager.injectVariable)=\(InjectInstaller.loaderPath)" }

    func isInjectionEnabled(_ udid: String) -> Bool { injectionStates[udid] ?? false }
    func isInjectionRemembered(_ udid: String) -> Bool { injectsAllSimulators || InjectionPreferences.isRemembered(udid) }
    func apps(for udid: String) -> [SimulatorApp] { appsByDevice[udid] ?? [] }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let all = try await SimulatorManager.allDevices()
            let booted = all.filter(\.isBooted)
            toolsAvailable = true
            injectsAllSimulators = InjectionPreferences.injectsAllSimulators
            var states: [String: Bool] = [:]
            for device in booted {
                states[device.udid] = await restoreInjection(on: device.udid)
            }
            restoredUDIDs.formIntersection(states.keys)
            devices = Self.ordered(all)
            injectionStates = states
            appsByDevice = appsByDevice.filter { states[$0.key] != nil }
            if let preferred = preferredUDID, all.contains(where: { $0.udid == preferred }) {
                selectedUDID = preferred
                preferredUDID = nil
            } else if selectedUDID == nil || !all.contains(where: { $0.udid == selectedUDID }) {
                selectedUDID = booted.first?.udid ?? all.first?.udid
            }
            message = booted.isEmpty ? "No simulator is running. Choose one and press Boot." : nil
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
        if devices.first(where: { $0.udid == udid })?.isBooted == false {
            objectWillChange.send()
            message = enabled ? "Injection turns on when this simulator boots." : "Injection disabled."
            return
        }
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

    func boot(_ udid: String? = nil) async {
        guard let udid = udid ?? selectedUDID else { return }
        let name = devices.first { $0.udid == udid }?.name ?? "simulator"
        await perform {
            try await SimulatorManager.boot(udid)
            self.openSimulatorApp()
            self.message = "Booted \(name)"
        }
        await refresh()
    }

    /// Running simulators first, then iPhones, iPads and the rest; newest runtime first within each group.
    private static func ordered(_ devices: [SimulatorDevice]) -> [SimulatorDevice] {
        func rank(_ device: SimulatorDevice) -> Int {
            if device.isBooted { return 0 }
            if device.name.hasPrefix("iPhone") { return 1 }
            if device.name.hasPrefix("iPad") { return 2 }
            return 3
        }
        return devices.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
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

    /// Schemes of each set-up project, for the Xcode section.
    @Published private(set) var xcodeSchemes: [String: [XcodeSchemeSetup.Scheme]] = [:]

    /// Asks for an .xcodeproj / .xcworkspace and adds the loader to its iOS app schemes, so Xcode Run keeps the camera.
    func setUpXcodeProject() {
        let panel = NSOpenPanel()
        panel.title = "Set Up Xcode Project"
        panel.message = "Choose the project or workspace you run from Xcode. Its iOS app schemes get "
            + "\(XcodeSchemeSetup.variable) in Run › Environment Variables."
        panel.prompt = "Set Up"
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setUpXcodeProject(at: url)
    }

    func setUpXcodeProject(at url: URL) {
        do {
            let container = try XcodeSchemeSetup.container(in: url)
            let changed = try XcodeSchemeSetup.setEnabled(true, in: container)
            let schemes = try XcodeSchemeSetup.schemes(in: container)
            let enabled = schemes.filter(\.isEnabled).map(\.name)
            if enabled.isEmpty {
                // Keep it listed so the skipped schemes and their reasons are visible.
                XcodeSchemeSetup.remember(container, true)
                message = "No iOS app scheme in \(container.lastPathComponent)."
            } else {
                message = "\(container.lastPathComponent): \(enabled.joined(separator: ", ")) "
                    + "\(changed.isEmpty ? "already set up" : "set up"). Stop and Run again in Xcode."
            }
        } catch {
            message = error.localizedDescription
        }
        reloadXcodeProjects()
    }

    func setScheme(_ scheme: XcodeSchemeSetup.Scheme, enabled: Bool, project: String) {
        do {
            let container = URL(fileURLWithPath: project)
            try XcodeSchemeSetup.setEnabled(enabled, in: container, schemeNames: [scheme.name], force: true)
            XcodeSchemeSetup.remember(container, true)
            message = "\(scheme.name): SimCamLite \(enabled ? "added" : "removed"). Stop and Run again in Xcode."
        } catch {
            message = error.localizedDescription
        }
        reloadXcodeProjects()
    }

    func removeXcodeProject(_ path: String) {
        let url = URL(fileURLWithPath: path)
        do {
            if FileManager.default.fileExists(atPath: path) {
                try XcodeSchemeSetup.setEnabled(false, in: url)
            }
            message = "Removed SimCamLite from \(url.lastPathComponent) schemes"
        } catch {
            message = error.localizedDescription
        }
        XcodeSchemeSetup.remember(url, false)
        reloadXcodeProjects()
    }

    /// Re-reads the scheme files, which may have been edited in Xcode or by `simcam xcode`.
    func reloadXcodeProjects() {
        xcodeProjects = XcodeSchemeSetup.projects
        var schemes: [String: [XcodeSchemeSetup.Scheme]] = [:]
        for path in xcodeProjects {
            schemes[path] = (try? XcodeSchemeSetup.schemes(in: URL(fileURLWithPath: path))) ?? []
        }
        xcodeSchemes = schemes
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
        if udids != Set(devices.filter(\.isBooted).map(\.udid)) || !udids.isSubset(of: restoredUDIDs)
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
