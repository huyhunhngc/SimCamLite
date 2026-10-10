import AppKit

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Talks to SimCamLite.app, launching it in the background when a command needs the engine.
enum AppConnection {
    @discardableResult
    static func send(_ request: ControlRequest, launchIfNeeded: Bool = true) async throws -> ControlResponse {
        let response: ControlResponse
        do {
            response = try ControlSocket.send(request)
        } catch ControlSocket.Failure.notRunning where launchIfNeeded {
            try await launchApp()
            response = try ControlSocket.send(request)
        }
        guard response.ok else { throw CLIError(response.error ?? "Request failed") }
        return response
    }

    /// Lets a running app pick up simulator changes made by the CLI; silently does nothing otherwise.
    static func notifySimulatorsChanged() {
        guard ControlSocket.isReachable() else { return }
        _ = try? ControlSocket.send(.refreshSimulators, timeout: 5)
    }

    static var isRunning: Bool { ControlSocket.isReachable() }

    static func launchApp() async throws {
        guard let url = appURL else {
            throw CLIError("SimCamLite.app not found. Build it with scripts/build.sh and open it once.")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        } catch {
            throw CLIError("Cannot open \(url.path): \(error.localizedDescription)")
        }
        for _ in 0..<150 {
            if ControlSocket.isReachable() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw CLIError("SimCamLite did not start its control socket at \(ControlPaths.socket)")
    }

    /// Prefers the app this binary is embedded in (SimCamLite.app/Contents/MacOS/simcam), so a symlinked CLI
    /// always drives the matching app build.
    static var appURL: URL? {
        if let executable = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if bundle.pathExtension == "app" { return bundle }
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: ControlPaths.appBundleID)
    }
}
