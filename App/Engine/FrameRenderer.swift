import CoreImage

struct RenderOptions: Equatable, Codable {
    var fill = true
    var rotation = 0
    var mirror = false
}

final class FrameRenderer {
    static let canvasSize = CGSize(width: CGFloat(SCL_SENSOR_HEIGHT), height: CGFloat(SCL_SENSOR_WIDTH))
    static let previewSize = CGSize(width: 360, height: 480)

    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private lazy var context = CIContext(options: [.workingColorSpace: colorSpace, .cacheIntermediates: false])
    private let black = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: canvasSize))

    func portrait(from image: CIImage?, options: RenderOptions) -> CIImage {
        guard var image else { return black }
        switch ((options.rotation % 4) + 4) % 4 {
        case 1: image = image.oriented(.right)
        case 2: image = image.oriented(.down)
        case 3: image = image.oriented(.left)
        default: break
        }
        if options.mirror {
            image = image.oriented(.upMirrored)
        }
        image = Self.normalized(image)
        let size = Self.canvasSize
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return black }
        let sx = size.width / extent.width
        let sy = size.height / extent.height
        let scale = options.fill ? max(sx, sy) : min(sx, sy)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offset = CGAffineTransform(translationX: (size.width - scaled.extent.width) / 2, y: (size.height - scaled.extent.height) / 2)
        return scaled.transformed(by: offset).composited(over: black).cropped(to: CGRect(origin: .zero, size: size))
    }

    @discardableResult
    func write(_ portrait: CIImage, stream: Int32) -> Bool {
        var slot: Int32 = 0
        guard let destination = scl_host_begin_frame(stream, &slot) else { return false }
        let sensor = Self.normalized(portrait.oriented(.left))
        let width = Int(SCL_SENSOR_WIDTH)
        let height = Int(SCL_SENSOR_HEIGHT)
        let rowBytes = width * 4
        context.render(sensor, toBitmap: destination, rowBytes: rowBytes, bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .BGRA8, colorSpace: colorSpace)
        scl_host_end_frame(stream, slot, UInt32(width), UInt32(height), UInt32(rowBytes))
        return true
    }

    func preview(_ portrait: CIImage) -> CGImage? {
        let scale = Self.previewSize.width / Self.canvasSize.width
        let image = portrait.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(image, from: CGRect(origin: .zero, size: Self.previewSize), format: .RGBA8, colorSpace: colorSpace)
    }

    private static func normalized(_ image: CIImage) -> CIImage {
        image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
    }
}
