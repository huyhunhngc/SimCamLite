import AppKit
import CoreImage

final class TestPatternSource: FrameSource {
    let title: String
    private let label: String
    private let size = CGSize(width: 1440, height: 1920)
    private lazy var background: CGImage? = makeBackground()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private var frameIndex: UInt64 = 0
    private let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    init(label: String) {
        self.label = label
        self.title = "Test pattern"
    }

    func start() {}
    func stop() {}

    func currentImage(at time: CFTimeInterval) -> CIImage? {
        frameIndex += 1
        guard let context = makeContext(), let background else { return nil }
        context.draw(background, in: CGRect(origin: .zero, size: size))

        let phase = time.truncatingRemainder(dividingBy: 4) / 4
        let ballX = 160 + (size.width - 320) * (0.5 + 0.5 * sin(phase * 2 * .pi))
        context.setFillColor(NSColor.systemYellow.cgColor)
        context.fillEllipse(in: CGRect(x: ballX - 70, y: 300, width: 140, height: 140))

        drawText(formatter.string(from: Date()), at: CGPoint(x: size.width / 2, y: 620), size: 110, weight: .bold, in: context)
        drawText("frame \(frameIndex)", at: CGPoint(x: size.width / 2, y: 520), size: 60, weight: .regular, in: context)

        guard let image = context.makeImage() else { return nil }
        return CIImage(cgImage: image)
    }

    private func makeContext() -> CGContext? {
        CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    private func makeBackground() -> CGImage? {
        guard let context = makeContext() else { return nil }
        let colors: [NSColor] = [.white, .systemYellow, .systemTeal, .systemGreen, .systemPink, .systemRed, .systemBlue]
        let barWidth = size.width / CGFloat(colors.count)
        for (index, color) in colors.enumerated() {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: CGFloat(index) * barWidth, y: size.height * 0.62, width: barWidth + 1, height: size.height * 0.38))
        }
        context.setFillColor(NSColor(white: 0.1, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.62))

        context.setStrokeColor(NSColor(white: 1, alpha: 0.18).cgColor)
        context.setLineWidth(2)
        stride(from: 0, through: size.width, by: 120).forEach { x in
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: size.height))
        }
        stride(from: 0, through: size.height, by: 120).forEach { y in
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.strokePath()

        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(6)
        context.strokeEllipse(in: CGRect(x: size.width / 2 - 360, y: size.height / 2 - 360, width: 720, height: 720))
        context.move(to: CGPoint(x: size.width / 2 - 60, y: size.height / 2))
        context.addLine(to: CGPoint(x: size.width / 2 + 60, y: size.height / 2))
        context.move(to: CGPoint(x: size.width / 2, y: size.height / 2 - 60))
        context.addLine(to: CGPoint(x: size.width / 2, y: size.height / 2 + 60))
        context.strokePath()

        context.setFillColor(NSColor.white.cgColor)
        let arrowTop = size.height * 0.62 - 40
        context.move(to: CGPoint(x: size.width / 2, y: arrowTop))
        context.addLine(to: CGPoint(x: size.width / 2 - 90, y: arrowTop - 130))
        context.addLine(to: CGPoint(x: size.width / 2 + 90, y: arrowTop - 130))
        context.closePath()
        context.fillPath()
        drawText("TOP", at: CGPoint(x: size.width / 2, y: arrowTop - 230), size: 80, weight: .heavy, in: context)
        drawText("L", at: CGPoint(x: 90, y: size.height / 2 - 50), size: 100, weight: .heavy, in: context)
        drawText("R", at: CGPoint(x: size.width - 90, y: size.height / 2 - 50), size: 100, weight: .heavy, in: context)
        drawText("SimCamLite · \(label)", at: CGPoint(x: size.width / 2, y: 140), size: 70, weight: .semibold, in: context)
        return context.makeImage()
    }

    private func drawText(_ text: String, at point: CGPoint, size fontSize: CGFloat, weight: NSFont.Weight, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor.white,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(x: point.x - bounds.width / 2, y: point.y)
        CTLineDraw(line, context)
    }
}
