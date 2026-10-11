import ArgumentParser
import Foundation

struct Xcode: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Make apps run from Xcode (with the debugger) load SimCamLite.",
        discussion: """
        Xcode Run replaces the simulator-wide injection with its own DYLD_INSERT_LIBRARIES. `setup` adds the \
        SimCamLite loader to the Run environment of each scheme that runs an iOS app (macOS / Mac Catalyst schemes are \
        skipped: the simulator loader would abort them). Safe to commit: a machine without SimCamLite ignores it. \
        Path defaults to the workspace or project in the current directory.
        """
    )

    enum Action: String, ExpressibleByArgument, CaseIterable {
        case setup, remove, status
    }

    @Argument(help: "setup | remove | status")
    var action: Action = .status

    @Argument(help: "An .xcworkspace, .xcodeproj or the directory containing one", completion: .file())
    var path: String?

    @Option(name: .long, help: "Only this scheme (repeatable)")
    var scheme: [String] = []

    @Flag(help: "With `setup`: also change schemes whose platform could not be determined")
    var force = false

    func run() throws {
        let url = URL(fileURLWithPath: path ?? FileManager.default.currentDirectoryPath).standardizedFileURL
        let container = try XcodeSchemeSetup.container(in: url)
        switch action {
        case .status:
            break
        case .setup, .remove:
            let enable = action == .setup
            if enable, !InjectInstaller.isInstalled {
                print("Note: the loader is not installed yet; open SimCamLite or run `simcam inject on` once.")
            }
            let changed = try XcodeSchemeSetup.setEnabled(enable, in: container, schemeNames: scheme, force: force)
            print(changed.isEmpty
                ? "No scheme changed."
                : "\(enable ? "Set up" : "Removed from") \(changed.map(\.name).joined(separator: ", ")).")
        }
        let rows = try XcodeSchemeSetup.schemes(in: container).map { s in
            [s.name, s.isEnabled ? "on" : "off", s.isShared ? "shared" : "user", s.skipReason ?? ""]
        }
        Output.table(rows, header: ["SCHEME", "SIMCAM", "KIND", "NOTE"])
        if action == .setup { print("Stop and Run again in Xcode to apply.") }
    }
}
