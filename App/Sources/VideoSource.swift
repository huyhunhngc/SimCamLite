import AVFoundation
import CoreImage

final class VideoSource: FrameSource {
    let url: URL
    let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private var orientation: CGImagePropertyOrientation = .up
    private var lastImage: CIImage?
    private var endObserver: NSObjectProtocol?
    private let lock = NSLock()

    init(url: URL) {
        self.url = url
        let item = AVPlayerItem(url: url)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ])
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
        Task { [weak self] in
            guard let track = try? await AVURLAsset(url: url).loadTracks(withMediaType: .video).first,
                  let transform = try? await track.load(.preferredTransform) else { return }
            self?.setOrientation(Self.orientation(for: transform))
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        player.pause()
    }

    var title: String { url.lastPathComponent }

    func start() {
        player.play()
    }

    func stop() {
        player.pause()
    }

    func hasNewFrame(at time: CFTimeInterval) -> Bool? {
        output.hasNewPixelBuffer(forItemTime: output.itemTime(forHostTime: time))
    }

    func currentImage(at time: CFTimeInterval) -> CIImage? {
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        lock.lock()
        defer { lock.unlock() }
        if output.hasNewPixelBuffer(forItemTime: itemTime),
           let buffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
            lastImage = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        }
        return lastImage
    }

    private func setOrientation(_ value: CGImagePropertyOrientation) {
        lock.lock()
        orientation = value
        lastImage = nil
        lock.unlock()
    }

    private static func orientation(for transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): .right
        case (0, -1, 1, 0): .left
        case (-1, 0, 0, -1): .down
        default: .up
        }
    }
}
