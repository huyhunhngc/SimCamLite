import ArgumentParser
import Foundation

@main
struct SimCam: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "simcam",
        abstract: "Control SimCamLite, the iOS Simulator camera emulator.",
        discussion: "Stream commands drive SimCamLite.app (opened in the background when needed) and share its state with the GUI.",
        version: "1.0",
        subcommands: [
            Start.self, Stop.self, Quit.self, Status.self, Fps.self, Profile.self,
            Source.self, Adjust.self, Pause.self, Resume.self, Cameras.self,
            Devices.self, Boot.self, Apps.self, Launch.self, Inject.self, Xcode.self,
        ]
    )
}

extension StreamTarget: EnumerableFlag {
    public static func help(for value: StreamTarget) -> ArgumentHelp? {
        value == .back ? "Back camera" : "Front camera"
    }
}

struct JSONFlag: ParsableArguments {
    @Flag(help: "Print JSON instead of text")
    var json = false
}

// MARK: - Streaming

struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Open SimCamLite if needed and start streaming.")

    @Option(help: "Frame rate (30 or 60)")
    var fps: Int?

    func run() async throws {
        Output.message(try await AppConnection.send(.startStreaming(fps: fps)))
    }
}

struct Stop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop streaming; SimCamLite keeps running.")

    func run() async throws {
        guard AppConnection.isRunning else { return print("SimCamLite is not running") }
        Output.message(try await AppConnection.send(.stopStreaming, launchIfNeeded: false))
    }
}

struct Quit: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Quit SimCamLite.")

    func run() async throws {
        guard AppConnection.isRunning else { return print("SimCamLite is not running") }
        Output.message(try await AppConnection.send(.quit, launchIfNeeded: false))
    }
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Show streaming state, sources and connected apps.")

    @OptionGroup var output: JSONFlag

    func run() async throws {
        guard AppConnection.isRunning else {
            if output.json { print(#"{"running": false}"#) } else { print("SimCamLite is not running") }
            return
        }
        let response = try await AppConnection.send(.status, launchIfNeeded: false)
        guard let status = response.status else { throw CLIError("No status in reply") }
        output.json ? try Output.json(status) : Output.status(status)
    }
}

struct Fps: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Set the frame rate sent to the simulator.")

    @Argument(help: "30 or 60")
    var fps: Int

    func run() async throws {
        Output.message(try await AppConnection.send(.setFrameRate(fps)))
    }
}

struct Profile: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Set the emulated device camera profile.")

    @Argument(help: "triple | dual | single")
    var profile: String

    func run() async throws {
        Output.message(try await AppConnection.send(.setProfile(profile)))
    }
}

struct Source: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Set the source of the back or front camera.",
        discussion: """
        SOURCE is one of:
          pattern        test pattern
          camera         a Mac camera (pick one with --device, see `simcam cameras`)
          qr <text>      a QR code generated from a link or text
          follow         front only: use the back camera source again
          <path>         an image or video file (videos loop)
        Setting a front source makes the front camera independent from the back camera.
        """
    )

    @Flag(exclusivity: .exclusive)
    var target: StreamTarget = .back

    @Argument(help: "pattern | camera | qr | follow | <path>")
    var source: String

    @Argument(help: "Link or text to encode, for the 'qr' source")
    var text: String?

    @Option(help: "Mac camera name (partial match) or unique ID")
    var device: String?

    func validate() throws {
        if source == "follow", target != .front {
            throw ValidationError("'follow' only applies to --front")
        }
        if device != nil, source != "camera" {
            throw ValidationError("--device requires the 'camera' source")
        }
        if source == "qr", text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
            throw ValidationError("'qr' needs the link or text to encode, e.g. simcam source qr https://example.com")
        }
        if text != nil, source != "qr" {
            throw ValidationError("Unexpected argument '\(text!)'")
        }
    }

    func run() async throws {
        let request: ControlRequest = switch source {
        case "follow": .followBack(true)
        case "pattern": .setSource(target: target, source: .pattern)
        case "camera": .setSource(target: target, source: .camera(query: device))
        case "qr": .setSource(target: target, source: .qr(text: text ?? ""))
        default: .setSource(target: target, source: .file(path: Self.absolutePath(source)))
        }
        Output.message(try await AppConnection.send(request))
    }

    private static func absolutePath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.hasPrefix("/") else { return expanded }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(expanded).standardizedFileURL.path
    }
}

enum FitMode: String, EnumerableFlag {
    case fill
    case fit
}

struct Adjust: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Change how a source is rendered.")

    @Flag(exclusivity: .exclusive)
    var target: StreamTarget = .back

    @Flag(help: "Fill (crop) or fit (letterbox) the camera frame")
    var mode: FitMode?

    @Option(help: "Rotation: 0, 90, 180 or 270 degrees")
    var rotate: Int?

    @Flag(inversion: .prefixedNo, help: "Mirror horizontally")
    var mirror: Bool?

    func validate() throws {
        if let rotate, ![0, 90, 180, 270].contains(rotate) {
            throw ValidationError("--rotate must be 0, 90, 180 or 270")
        }
        if mode == nil, rotate == nil, mirror == nil {
            throw ValidationError("Pass at least one of --fill, --fit, --rotate, --mirror, --no-mirror")
        }
    }

    func run() async throws {
        let response = try await AppConnection.send(.adjust(target: target, fill: mode.map { $0 == .fill },
                                                            rotation: rotate.map { $0 / 90 }, mirror: mirror))
        if let status = response.status { Output.status(status) }
    }
}

struct Pause: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Pause a video source.")

    @Flag(exclusivity: .exclusive)
    var target: StreamTarget = .back

    func run() async throws {
        Output.message(try await AppConnection.send(.pause(target: target, paused: true)))
    }
}

struct Resume: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Resume a paused video source.")

    @Flag(exclusivity: .exclusive)
    var target: StreamTarget = .back

    func run() async throws {
        Output.message(try await AppConnection.send(.pause(target: target, paused: false)))
    }
}

struct Cameras: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List Mac cameras usable as a source.")

    @OptionGroup var output: JSONFlag

    func run() async throws {
        let cameras = try await AppConnection.send(.listCameras).cameras ?? []
        if output.json { return try Output.json(cameras) }
        if cameras.isEmpty { return print("No Mac camera found") }
        Output.table(cameras.map { [$0.name, $0.id, $0.active.map(\.rawValue).joined(separator: ",")] },
                     header: ["NAME", "ID", "IN USE"])
    }
}
