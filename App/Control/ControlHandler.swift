import AppKit
import AVFoundation

/// Applies `simcam` requests to the same model the GUI observes, so both always show one state.
@MainActor
final class ControlHandler {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func handle(_ request: ControlRequest) async -> ControlResponse {
        switch request {
        case .status:
            return reply()

        case .startStreaming(let fps):
            if let fps {
                guard let rate = FrameRate(rawValue: fps) else { return invalidFrameRate(fps) }
                model.frameRate = rate
            }
            model.startStreaming()
            return reply("Streaming \(model.frameRate.title)")

        case .stopStreaming:
            model.stopStreaming()
            return reply("Streaming stopped")

        case .quit:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
            return ControlResponse(message: "SimCamLite is quitting")

        case .setFrameRate(let fps):
            guard let rate = FrameRate(rawValue: fps) else { return invalidFrameRate(fps) }
            model.frameRate = rate
            return reply("Frame rate \(rate.title)")

        case .setProfile(let name):
            guard let profile = DeviceProfile(name: name) else {
                return .failure("Unknown profile '\(name)'. Use: \(DeviceProfile.allCases.map(\.name).joined(separator: ", "))")
            }
            model.deviceProfile = profile
            return reply("Device profile \(profile.title) (applies to apps launched afterwards)")

        case .setSource(let target, let spec):
            return setSource(spec, on: target)

        case .followBack(let follows):
            model.frontFollowsBack = follows
            return reply(follows ? "Front camera uses the back source" : "Front camera uses its own source")

        case .adjust(let target, let fill, let rotation, let mirror):
            let stream = stream(for: target)
            if let fill { stream.options.fill = fill }
            if let rotation { stream.options.rotation = ((rotation % 4) + 4) % 4 }
            if let mirror { stream.options.mirror = mirror }
            return reply()

        case .pause(let target, let paused):
            let stream = stream(for: target)
            guard stream.videoSource != nil else { return .failure("\(stream.label) source is not a video") }
            stream.isPaused = paused
            return reply(paused ? "Paused" : "Playing")

        case .listCameras:
            let cameras = MacCameraSource.availableDevices.map { device in
                CameraInfo(id: device.uniqueID, name: device.localizedName,
                           active: StreamTarget.allCases.filter { stream(for: $0).cameraDeviceID == device.uniqueID })
            }
            return ControlResponse(cameras: cameras)

        case .refreshSimulators:
            await model.simulators.refresh()
            return ControlResponse()
        }
    }

    private func setSource(_ spec: SourceSpec, on target: StreamTarget) -> ControlResponse {
        let stream = stream(for: target)
        stream.use(spec)
        if let error = stream.errorMessage {
            return .failure(error)
        }
        if target == .front {
            model.frontFollowsBack = false
        }
        return reply("\(stream.label): \(stream.source.title)")
    }

    private func stream(for target: StreamTarget) -> StreamController {
        target == .front ? model.front : model.back
    }

    private func invalidFrameRate(_ fps: Int) -> ControlResponse {
        .failure("Unsupported frame rate \(fps). Use: \(FrameRate.allCases.map { String($0.rawValue) }.joined(separator: ", "))")
    }

    private func reply(_ message: String? = nil) -> ControlResponse {
        ControlResponse(message: message, status: model.snapshot())
    }
}

extension DeviceProfile {
    var name: String {
        switch self {
        case .triple: "triple"
        case .dualWide: "dual"
        case .single: "single"
        }
    }

    init?(name: String) {
        guard let profile = Self.allCases.first(where: { $0.name == name.lowercased() }) else { return nil }
        self = profile
    }
}

extension AppModel {
    func snapshot() -> StatusSnapshot {
        StatusSnapshot(
            streaming: isStreaming,
            fps: frameRate.rawValue,
            profile: deviceProfile.name,
            frontFollowsBack: frontFollowsBack,
            back: back.snapshot(),
            front: front.snapshot(),
            clients: clients.map {
                ClientSnapshot(pid: $0.pid, bundleID: $0.bundleID, processName: $0.processName,
                               camera: $0.cameraDescription, frames: $0.framesDelivered, photos: $0.photoCount)
            },
            injectInstalled: injectInstalled,
            sharedMemoryReady: sharedMemoryReady
        )
    }
}

extension StreamController {
    func snapshot() -> StreamSnapshot {
        StreamSnapshot(kind: kind.rawValue, title: source.title, filePath: fileURL?.path,
                       fill: options.fill, rotation: options.rotation, mirror: options.mirror,
                       paused: isPaused, error: errorMessage)
    }
}
