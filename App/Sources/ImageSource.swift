import CoreImage
import Foundation

final class ImageSource: FrameSource {
    let url: URL
    private let image: CIImage?

    init(url: URL) {
        self.url = url
        let loaded = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
        image = loaded.map { $0.transformed(by: CGAffineTransform(translationX: -$0.extent.minX, y: -$0.extent.minY)) }
    }

    var title: String { url.lastPathComponent }
    var isValid: Bool { image != nil }

    func start() {}
    func stop() {}

    func currentImage(at time: CFTimeInterval) -> CIImage? {
        image
    }
}
