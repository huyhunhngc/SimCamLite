import CoreImage

protocol FrameSource: AnyObject {
    var title: String { get }
    func start()
    func stop()
    func currentImage(at time: CFTimeInterval) -> CIImage?
}

enum SourceKind: String, CaseIterable, Identifiable {
    case testPattern
    case image
    case video
    case macCamera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .testPattern: "Test pattern"
        case .image: "Image"
        case .video: "Video"
        case .macCamera: "Mac camera"
        }
    }

    var symbol: String {
        switch self {
        case .testPattern: "square.grid.3x3.fill"
        case .image: "photo"
        case .video: "film"
        case .macCamera: "web.camera"
        }
    }
}
