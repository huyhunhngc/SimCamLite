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
    private var lastWrite: [Int32: CFTimeInterval] = [:]
    private var lastPreview: CFTimeInterval = 0
    private var backPreview: CGImage?
    private var frontPreview: CGImage?
    private var lastClients: CFTimeInterval = 0
    private static let frameInterval: CFTimeInterval = 1.0 / 30
    private static let pollInterval: CFTimeInterval = 1.0 / 120
    private static let idleInterval: CFTimeInterval = 0.1

    func update(_ change: (inout Config) -> Void) {
        lock.lock()
        change(&config)
        lock.unlock()
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.pollInterval, leeway: .milliseconds(1))
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
        let time = CACurrentMediaTime()
        let backStream = Int32(SCLStreamBack)
        let frontStream = Int32(SCLStreamFront)
        let backDue = isDue(config.backSource, stream: backStream, at: time)
        let frontDue = config.frontFollowsBack ? backDue : isDue(config.frontSource, stream: frontStream, at: time)
        let previewDue = (backDue || frontDue) && time - lastPreview >= Self.idleInterval - Self.pollInterval

        autoreleasepool {
            var back: CIImage?
            var front: CIImage?
            if backDue {
                back = renderer.portrait(from: config.backSource?.currentImage(at: time), options: config.backOptions)
            }
            if config.frontFollowsBack {
                front = back
            } else if frontDue {
                front = renderer.portrait(from: config.frontSource?.currentImage(at: time), options: config.frontOptions)
            }
            if backDue, let back {
                renderer.write(back, stream: backStream)
                lastWrite[backStream] = time
            }
            if frontDue, let front {
                renderer.write(front, stream: frontStream)
                lastWrite[frontStream] = time
            }
            if previewDue, let onPreview {
                lastPreview = time
                if let back { backPreview = renderer.preview(back) }
                if let front { frontPreview = config.frontFollowsBack ? backPreview : renderer.preview(front) }
                let backPreview = backPreview
                let frontPreview = frontPreview
                DispatchQueue.main.async { onPreview(backPreview, frontPreview) }
            }
        }

        if time - lastClients >= 0.5, let onClients {
            lastClients = time
            let clients = readClients()
            DispatchQueue.main.async { onClients(clients) }
        }
    }

    private func isDue(_ source: FrameSource?, stream: Int32, at time: CFTimeInterval) -> Bool {
        let elapsed = time - (lastWrite[stream] ?? 0)
        let threshold = Self.frameInterval - Self.pollInterval / 2
        guard let hasNew = source?.hasNewFrame(at: time) else { return elapsed >= threshold }
        return (hasNew && elapsed >= threshold) || elapsed >= Self.idleInterval
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
