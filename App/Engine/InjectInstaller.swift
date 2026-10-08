import Foundation

enum InjectInstaller {
    static let directory = URL(fileURLWithPath: String(cString: SCL_SHM_DIRECTORY))
    static let loaderPath = directory.appendingPathComponent("SimCamLiteLoader.dylib").path
    static let frameworkName = "SimCamLiteInject.framework"
    static let loaderName = "SimCamLiteLoader.dylib"

    static var bundledDirectory: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("Inject", isDirectory: true)
    }

    static var isInstalled: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: loaderPath)
            && fm.fileExists(atPath: directory.appendingPathComponent(frameworkName).appendingPathComponent("SimCamLiteInject").path)
    }

    @discardableResult
    static func install() throws -> Bool {
        guard let source = bundledDirectory, FileManager.default.fileExists(atPath: source.appendingPathComponent(loaderName).path) else {
            return false
        }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o777])
        for name in [frameworkName, loaderName] {
            let destination = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source.appendingPathComponent(name), to: destination)
        }
        return true
    }
}
