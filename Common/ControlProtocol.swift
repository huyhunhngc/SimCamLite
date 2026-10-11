import Foundation

/// Messages exchanged between `simcam` and SimCamLite.app over the control socket (one JSON request and reply per connection).
enum ControlPaths {
    static let appBundleID = "dev.ifateam.simcamlite"

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SimCamLite", isDirectory: true)
    }

    static var socket: String { directory.appendingPathComponent("control.sock").path }
}

enum StreamTarget: String, Codable, CaseIterable {
    case back
    case front
}

enum SourceSpec: Codable, Equatable {
    case pattern
    case file(path: String)
    /// Matches a Mac camera by unique ID or by a case-insensitive part of its name; nil picks the first camera.
    case camera(query: String?)
    /// A QR code generated from the text, e.g. a URL to test a scanner.
    case qr(text: String)
}

enum ControlRequest: Codable {
    case status
    case startStreaming(fps: Int?)
    case stopStreaming
    case quit
    case setFrameRate(Int)
    case setProfile(String)
    case setSource(target: StreamTarget, source: SourceSpec)
    case followBack(Bool)
    case adjust(target: StreamTarget, fill: Bool?, rotation: Int?, mirror: Bool?)
    case pause(target: StreamTarget, paused: Bool)
    case listCameras
    case refreshSimulators
}

struct StreamSnapshot: Codable {
    var kind: String
    var title: String
    var filePath: String?
    var fill: Bool
    var rotation: Int
    var mirror: Bool
    var paused: Bool
    var error: String?
}

struct ClientSnapshot: Codable {
    var pid: Int32
    var bundleID: String
    var processName: String
    var camera: String
    var frames: UInt64
    var photos: UInt64
}

struct StatusSnapshot: Codable {
    var streaming: Bool
    var fps: Int
    var profile: String
    var frontFollowsBack: Bool
    var back: StreamSnapshot
    var front: StreamSnapshot
    var clients: [ClientSnapshot]
    var injectInstalled: Bool
    var sharedMemoryReady: Bool
}

struct CameraInfo: Codable {
    var id: String
    var name: String
    var active: [StreamTarget]
}

struct ControlResponse: Codable {
    var ok = true
    var error: String?
    var message: String?
    var status: StatusSnapshot?
    var cameras: [CameraInfo]?

    static func failure(_ error: String) -> ControlResponse { ControlResponse(ok: false, error: error) }
}
