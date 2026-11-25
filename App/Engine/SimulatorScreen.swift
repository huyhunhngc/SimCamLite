import Foundation
import Combine
import IOSurface

/// The selected simulator's live screen and input, shown in the Camera screen's simulator pane.
@MainActor
final class SimulatorScreen: ObservableObject {
    enum State: Equatable {
        case detached
        case attaching
        case attached
        case failed(String)
    }

    @Published private(set) var state: State = .detached
    /// Display size in pixels; the pane keeps this aspect ratio.
    @Published private(set) var pixelSize: CGSize?
    /// Surface and frame ticks go to the screen layer outside SwiftUI state, like `PreviewFeed.frames`.
    let surface = CurrentValueSubject<IOSurface?, Never>(nil)
    let frames = PassthroughSubject<Void, Never>()
    private var bridge: SCLSimulatorScreen?
    private var udid: String?

    /// Attaches to `udid` and keeps retrying while it fails (a simulator that has just booted needs a few
    /// seconds before its input service answers). Returns when the calling task is cancelled.
    func attach(udid: String) async {
        guard self.udid != udid || bridge == nil else { return }
        detach()
        self.udid = udid
        while bridge == nil {
            guard self.udid == udid else { return }
            guard !Task.isCancelled else { return detach() }
            state = .attaching
            let result = await Self.connect(udid: udid)
            guard self.udid == udid, !Task.isCancelled else { continue }
            switch result {
            case let .success(box):
                use(box.value)
            case let .failure(error):
                state = .failed(error.localizedDescription)
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func detach() {
        bridge?.detach()
        bridge = nil
        udid = nil
        surface.send(nil)
        pixelSize = nil
        state = .detached
    }

    func sendTouch(_ phase: SCLTouchPhase, at point: CGPoint, edge: SCLTouchEdge) {
        bridge?.sendTouch(phase, x: point.x, y: point.y, edge: edge)
    }

    func sendKey(_ usage: UInt32, down: Bool) {
        bridge?.sendKey(usage, down: down)
    }

    func press(_ button: Button) {
        bridge?.sendButton(button.rawValue, down: true)
        bridge?.sendButton(button.rawValue, down: false)
    }

    /// HID consumer usages (page 0x0C).
    enum Button: UInt16 {
        case home = 0x40
        case lock = 0x30
    }

    private func use(_ bridge: SCLSimulatorScreen) {
        self.bridge = bridge
        bridge.onSurfaceChange = { [weak self] in self?.show($0) }
        bridge.onFrame = { [weak self] in self?.frames.send() }
        show(bridge.surface)
        state = .attached
    }

    private func show(_ surface: IOSurface?) {
        self.surface.send(surface)
        let size = surface.map { CGSize(width: $0.width, height: $0.height) }
        if let size, size != pixelSize { pixelSize = size }
    }

    /// Boxed so the non-Sendable bridge can leave the background task that built it.
    private struct Box: @unchecked Sendable { let value: SCLSimulatorScreen }

    private static func connect(udid: String) async -> Result<Box, Error> {
        await Task.detached(priority: .userInitiated) {
            Result {
                Box(value: try SCLSimulatorScreen(udid: udid, developerDir: developerDir))
            }
        }.value
    }

    /// The active Xcode, as `xcrun simctl` uses it.
    private nonisolated static let developerDir: String = {
        if let path = ProcessInfo.processInfo.environment["DEVELOPER_DIR"], !path.isEmpty { return path }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        process.standardOutput = pipe
        try? process.run()
        process.waitUntilExit()
        let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? "/Applications/Xcode.app/Contents/Developer" : path
    }()
}
