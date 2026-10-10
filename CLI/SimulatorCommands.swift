import ArgumentParser
import Foundation

struct DeviceOption: ParsableArguments {
    @Option(name: [.short, .long], help: "Booted simulator name or UDID (default: the only booted one)")
    var device: String?

    func resolve() async throws -> SimulatorDevice {
        try await Simulators.booted(matching: device)
    }
}

enum Simulators {
    static func booted(matching query: String?) async throws -> SimulatorDevice {
        let booted = try await SimulatorManager.bootedDevices()
        guard !booted.isEmpty else { throw CLIError("No booted simulator. Start one with `simcam boot <name>`.") }
        guard let query else {
            guard booted.count == 1 else {
                throw CLIError("Several simulators are booted; pick one with --device:\n" + list(booted))
            }
            return booted[0]
        }
        return try match(query, in: booted, kind: "booted simulator")
    }

    static func match(_ query: String, in devices: [SimulatorDevice], kind: String) throws -> SimulatorDevice {
        if let device = devices.first(where: { $0.udid.caseInsensitiveCompare(query) == .orderedSame }) { return device }
        let exact = devices.filter { $0.name.caseInsensitiveCompare(query) == .orderedSame }
        if let first = exact.first { return first }
        let partial = devices.filter { $0.name.localizedCaseInsensitiveContains(query) }
        if Set(partial.map(\.name)).count == 1, let first = partial.first { return first }
        if partial.isEmpty { throw CLIError("No \(kind) matches '\(query)'. See `simcam devices`.") }
        throw CLIError("'\(query)' matches several devices; be more specific:\n" + list(partial))
    }

    static func list(_ devices: [SimulatorDevice]) -> String {
        devices.map { "  \($0.name) (\($0.runtime)) \($0.udid)" }.joined(separator: "\n")
    }

    /// The inject library lives in /Users/Shared/SimCamLite and is installed by the app on launch.
    static func requireInjectLibrary() async throws {
        guard !InjectInstaller.isInstalled else { return }
        try await AppConnection.send(.status)
        guard InjectInstaller.isInstalled else {
            throw CLIError("Inject library missing at \(InjectInstaller.loaderPath). Open SimCamLite › Permissions & Setup.")
        }
    }

    static func openSimulatorApp(udid: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Simulator"] + (udid.map { ["--args", "-CurrentDeviceUDID", $0] } ?? [])
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CLIError("Cannot open Simulator.app") }
    }
}

struct Devices: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List iOS simulators.")

    @Flag(help: "Only booted simulators")
    var booted = false

    @OptionGroup var output: JSONFlag

    struct Entry: Encodable {
        let name: String
        let runtime: String
        let state: String
        let udid: String
        let injection: Bool?
    }

    func run() async throws {
        let devices = booted ? try await SimulatorManager.bootedDevices() : try await SimulatorManager.allDevices()
        var entries: [Entry] = []
        for device in devices {
            let injection = device.isBooted ? await SimulatorManager.isInjectionEnabled(on: device.udid) : nil
            entries.append(Entry(name: device.name, runtime: device.runtime, state: device.state, udid: device.udid, injection: injection))
        }
        if output.json { return try Output.json(entries) }
        if entries.isEmpty { return print(booted ? "No booted simulator" : "No iOS simulator available") }
        Output.table(entries.map { entry in
            let injection = entry.injection.map { $0 ? "on" : "off" } ?? "-"
            return [entry.state == "Booted" ? "●" : " ", entry.name, entry.runtime, entry.state, injection, entry.udid]
        }, header: [" ", "NAME", "RUNTIME", "STATE", "INJECT", "UDID"])
    }
}

struct Boot: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start a simulator.",
        discussion: "Without a name, opens Simulator.app with its last used device."
    )

    @Argument(help: "Simulator name (partial match) or UDID")
    var device: String?

    @Option(help: "Runtime filter, e.g. 18.2 or \"iOS 18\"")
    var runtime: String?

    @Flag(help: "Wait until the simulator finished booting")
    var wait = false

    @Flag(help: "Enable SimCamLite injection for every app on this simulator")
    var inject = false

    func validate() throws {
        if device == nil, runtime != nil || inject || wait {
            throw ValidationError("--runtime, --wait and --inject need a simulator name")
        }
    }

    func run() async throws {
        guard let device else {
            try Simulators.openSimulatorApp()
            return print("Opened Simulator.app")
        }
        var candidates = try await SimulatorManager.allDevices()
        if let runtime {
            let version = runtime.split { !$0.isNumber }.compactMap { Int($0) }
            candidates = candidates.filter { $0.runtimeVersion.starts(with: version) }
        }
        let target = try Simulators.match(device, in: candidates, kind: "simulator")
        if target.isBooted {
            print("\(target.name) (\(target.runtime)) is already booted")
        } else {
            try await SimulatorManager.boot(target.udid)
            print("Booted \(target.name) (\(target.runtime))")
        }
        try Simulators.openSimulatorApp(udid: target.udid)
        if wait || inject {
            try await SimulatorManager.run(["simctl", "bootstatus", target.udid, "-b"])
        }
        if inject {
            try await Simulators.requireInjectLibrary()
            try await SimulatorManager.setInjectionEnabled(true, on: target.udid)
            print("Injection enabled")
        }
        AppConnection.notifySimulatorsChanged()
    }
}

struct Apps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List user apps installed on a booted simulator.")

    @OptionGroup var target: DeviceOption
    @OptionGroup var output: JSONFlag

    struct Entry: Encodable {
        let name: String
        let bundleID: String
    }

    func run() async throws {
        let device = try await target.resolve()
        let apps = try await SimulatorManager.userApps(on: device.udid)
        if output.json { return try Output.json(apps.map { Entry(name: $0.name, bundleID: $0.bundleID) }) }
        if apps.isEmpty { return print("No user apps on \(device.name)") }
        Output.table(apps.map { [$0.name, $0.bundleID] }, header: ["NAME", "BUNDLE ID"])
    }
}

struct Launch: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Launch (or relaunch) an app with SimCamLite injected.")

    @Argument(help: "Bundle ID or app name")
    var app: String

    @OptionGroup var target: DeviceOption

    func run() async throws {
        let device = try await target.resolve()
        let apps = try await SimulatorManager.userApps(on: device.udid)
        let match = apps.first { $0.bundleID == app }
            ?? apps.first { $0.name.caseInsensitiveCompare(app) == .orderedSame }
        guard let match else {
            throw CLIError("No user app '\(app)' on \(device.name). See `simcam apps`.")
        }
        try await Simulators.requireInjectLibrary()
        try await SimulatorManager.launch(match.bundleID, on: device.udid)
        print("Launched \(match.name) (\(match.bundleID)) on \(device.name) with SimCamLite")
        if !AppConnection.isRunning {
            print("Note: SimCamLite is not running, so the app shows \"Host app is not running\". Run `simcam start`.")
        }
    }
}

struct Inject: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inject SimCamLite into every app launched on a simulator.",
        discussion: """
        `launchctl setenv` inside the simulator is lost when it shuts down. With --persist (or `inject auto on` for \
        every simulator) SimCamLite.app re-applies it each time the simulator boots, as long as the app is running. \
        `off` also forgets the simulator. Apps already running must be relaunched to pick up a change.
        """
    )

    enum Action: String, ExpressibleByArgument, CaseIterable {
        case on, off, status, auto
    }

    enum Setting: String, ExpressibleByArgument, CaseIterable {
        case on, off, status
    }

    @Argument(help: "on | off | status | auto")
    var action: Action = .status

    @Argument(help: "For `auto`: on | off | status — inject into every simulator as it boots")
    var setting: Setting?

    @OptionGroup var target: DeviceOption

    @Flag(help: "Apply to every booted simulator")
    var all = false

    @Flag(help: "With `on`: remember it and restore it after the simulator restarts")
    var persist = false

    func validate() throws {
        if setting != nil, action != .auto { throw ValidationError("on | off | status only follows `auto`") }
        if persist, action != .on { throw ValidationError("--persist only applies to `inject on`") }
    }

    func run() async throws {
        if action == .auto { return try await runAuto() }
        let devices = all ? try await SimulatorManager.bootedDevices() : [try await target.resolve()]
        if action == .on { try await Simulators.requireInjectLibrary() }
        for device in devices {
            if action != .status {
                try await SimulatorManager.setInjectionEnabled(action == .on, on: device.udid)
                if persist || action == .off { InjectionPreferences.remember(action == .on, udid: device.udid) }
            }
            print(Self.describe(device, enabled: await SimulatorManager.isInjectionEnabled(on: device.udid)))
        }
        if action == .status, InjectionPreferences.injectsAllSimulators {
            print("Auto-inject: on (every simulator as it boots)")
        }
        if persist { try await Self.ensureAppRunning() }
        if action != .status { AppConnection.notifySimulatorsChanged() }
    }

    private func runAuto() async throws {
        switch setting ?? .status {
        case .status:
            break
        case .on:
            try await Simulators.requireInjectLibrary()
            InjectionPreferences.injectsAllSimulators = true
            for device in try await SimulatorManager.bootedDevices() {
                guard !(await SimulatorManager.isInjectionEnabled(on: device.udid)) else { continue }
                try await SimulatorManager.setInjectionEnabled(true, on: device.udid)
                print(Self.describe(device, enabled: await SimulatorManager.isInjectionEnabled(on: device.udid)))
            }
            try await Self.ensureAppRunning()
            AppConnection.notifySimulatorsChanged()
        case .off:
            InjectionPreferences.injectsAllSimulators = false
            AppConnection.notifySimulatorsChanged()
        }
        print("Auto-inject: \(InjectionPreferences.injectsAllSimulators ? "on (every simulator as it boots)" : "off")")
    }

    static func describe(_ device: SimulatorDevice, enabled: Bool) -> String {
        let persistent = InjectionPreferences.shouldInject(device.udid) ? ", restored on boot" : ""
        return "\(device.name) (\(device.runtime)): injection \(enabled ? "on" : "off")\(persistent)"
    }

    /// Restoring injection after a boot is done by SimCamLite.app, so it has to be running.
    private static func ensureAppRunning() async throws {
        guard !AppConnection.isRunning else { return }
        try await AppConnection.launchApp()
        print("Started SimCamLite.app in the background; it restores injection when simulators boot.")
    }
}
