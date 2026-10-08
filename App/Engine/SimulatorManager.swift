import Foundation

struct SimulatorDevice: Identifiable, Hashable {
    let udid: String
    let name: String
    let runtime: String
    var id: String { udid }
}

struct SimulatorApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

enum SimulatorManager {
    static let injectVariable = "DYLD_INSERT_LIBRARIES"

    struct CommandError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @discardableResult
    static func run(_ arguments: [String], environment: [String: String] = [:]) async throws -> Data {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = arguments
            if !environment.isEmpty {
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
            }
            let output = Pipe()
            let errors = Pipe()
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                throw CommandError(message: message.isEmpty ? "xcrun \(arguments.joined(separator: " ")) failed" : message)
            }
            return data
        }.value
    }

    static func bootedDevices() async throws -> [SimulatorDevice] {
        let data = try await run(["simctl", "list", "devices", "booted", "-j"])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = json["devices"] as? [String: [[String: Any]]] else { return [] }
        var devices: [SimulatorDevice] = []
        for (runtime, entries) in runtimes {
            let runtimeName = runtime.components(separatedBy: ".").last?.replacingOccurrences(of: "-", with: " ") ?? runtime
            for entry in entries where (entry["state"] as? String) == "Booted" {
                guard let udid = entry["udid"] as? String, let name = entry["name"] as? String else { continue }
                devices.append(SimulatorDevice(udid: udid, name: name, runtime: runtimeName))
            }
        }
        return devices.sorted { $0.name < $1.name }
    }

    static func isInjectionEnabled(on udid: String) async -> Bool {
        guard let data = try? await run(["simctl", "spawn", udid, "launchctl", "getenv", injectVariable]) else { return false }
        return String(decoding: data, as: UTF8.self).contains(InjectInstaller.loaderPath)
    }

    static func setInjectionEnabled(_ enabled: Bool, on udid: String) async throws {
        if enabled {
            try await run(["simctl", "spawn", udid, "launchctl", "setenv", injectVariable, InjectInstaller.loaderPath])
        } else {
            try await run(["simctl", "spawn", udid, "launchctl", "unsetenv", injectVariable])
        }
    }

    static func userApps(on udid: String) async throws -> [SimulatorApp] {
        let data = try await run(["simctl", "listapps", udid])
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: Any]] else { return [] }
        return plist.compactMap { bundleID, info in
            guard (info["ApplicationType"] as? String) == "User" else { return nil }
            let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? bundleID
            return SimulatorApp(bundleID: bundleID, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func launch(_ bundleID: String, on udid: String) async throws {
        try await run(["simctl", "launch", "--terminate-running-process", udid, bundleID],
                      environment: ["SIMCTL_CHILD_\(injectVariable)": InjectInstaller.loaderPath])
    }
}
