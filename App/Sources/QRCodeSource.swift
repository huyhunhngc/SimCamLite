import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// A QR code generated from text (usually a URL) on a white card, so scanners can be tested without a printed code.
final class QRCodeSource: FrameSource {
    let text: String
    private let image: CIImage?

    init(text: String) {
        self.text = text
        image = Self.render(text)
    }

    var title: String { "QR · \(text)" }
    var isValid: Bool { image != nil }

    func start() {}
    func stop() {}

    func currentImage(at time: CFTimeInterval) -> CIImage? {
        image
    }

    private static let size = CGSize(width: 1440, height: 1920)

    private static func render(_ text: String) -> CIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage, code.extent.width > 0 else { return nil }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let codeImage = CIContext().createCGImage(code, from: code.extent),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        // Whole pixels per module keep the edges sharp; the generator already adds the quiet zone.
        // 820 pt stays inside the centre ~880 pt a full-screen (19.5:9) aspect-fill preview shows of the 3:4 frame.
        let modules = code.extent.width
        let side = floor(820 / modules) * modules
        context.interpolationQuality = .none
        context.draw(codeImage, in: CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2 + 120, width: side, height: side))

        let shown = text.count > 60 ? String(text.prefix(57)) + "…" : text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 52, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: shown, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let scale = min(1, 820 / max(bounds.width, 1))
        context.saveGState()
        context.translateBy(x: (size.width - bounds.width * scale) / 2, y: (size.height - side) / 2 - 60)
        context.scaleBy(x: scale, y: scale)
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()

        return context.makeImage().map { CIImage(cgImage: $0) }
    }
}
