import CoreImage
import QuartzCore

struct ConnectedClient: Identifiable, Equatable {
    let pid: Int32
    let bundleID: String
    let processName: String
    let cameraState: UInt32
    let framesDelivered: UInt64
    let photoCount: UInt64
    let outputWidth: UInt32
    let outputHeight: UInt32

    var id: Int32 { pid }

    var cameraDescription: String {
        switch cameraState {
        case UInt32(SCLClientCameraBack): "Back camera"
        case UInt32(SCLClientCameraFront): "Front camera"
        default: "Idle"
        }
    }
}

final class RenderPipeline: @unchecked Sendable {
    struct Config {
        var backSource: FrameSource?
        var frontSource: FrameSource?
        var frontFollowsBack = true
        var backOptions = RenderOptions()
        var frontOptions = RenderOptions()
        var deviceProfile: UInt32 = UInt32(SCLDeviceProfileTriple)
    }

    var onPreview: ((CGImage?, CGImage?) -> Void)?
    var onClients: (([ConnectedClient]) -> Void)?

    private let queue = DispatchQueue(label: "dev.ifateam.simcamlite.render", qos: .userInteractive)
    private let lock = NSLock()
    private let renderer = FrameRenderer()
    private var config = Config()
    private var timer: DispatchSourceTimer?
    private var tick: UInt64 = 0

    func update(_ change: (inout Config) -> Void) {
        lock.lock()
        change(&config)
        lock.unlock()
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(Int(1_000_000_000 / 30)), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.renderFrame() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func renderFrame() {
        lock.lock()
        let config = self.config
        lock.unlock()

        guard scl_host_open() else { return }
        scl_host_heartbeat(config.deviceProfile)
        tick += 1
        let time = CACurrentMediaTime()

        autoreleasepool {
            let back = renderer.portrait(from: config.backSource?.currentImage(at: time), options: config.backOptions)
            renderer.write(back, stream: Int32(SCLStreamBack))
            let front: CIImage
            if config.frontFollowsBack {
                front = back
            } else {
                front = renderer.portrait(from: config.frontSource?.currentImage(at: time), options: config.frontOptions)
            }
            renderer.write(front, stream: Int32(SCLStreamFront))

            if tick % 3 == 0, let onPreview {
                let backPreview = renderer.preview(back)
                let frontPreview = config.frontFollowsBack ? backPreview : renderer.preview(front)
                DispatchQueue.main.async { onPreview(backPreview, frontPreview) }
            }
        }

        if tick % 15 == 0, let onClients {
            let clients = readClients()
            DispatchQueue.main.async { onClients(clients) }
        }
    }

    private func readClients() -> [ConnectedClient] {
        var result: [ConnectedClient] = []
        for index in 0..<Int32(SCL_MAX_CLIENTS) {
            var info = SCLClientInfo()
            guard scl_host_read_client(index, &info) else { continue }
            result.append(ConnectedClient(
                pid: info.pid,
                bundleID: Self.string(from: info.bundleID),
                processName: Self.string(from: info.processName),
                cameraState: info.cameraState,
                framesDelivered: info.framesDelivered,
                photoCount: info.photoCount,
                outputWidth: info.outputWidth,
                outputHeight: info.outputHeight
            ))
        }
        return result
    }

    private static func string<T>(from tuple: T) -> String {
        withUnsafeBytes(of: tuple) { raw in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
    }
}
