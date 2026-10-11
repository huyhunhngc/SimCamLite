import Foundation

enum RecentFiles {
    private static let key = "recentSourceFiles"
    private static let limit = 8

    static var urls: [URL] {
        (UserDefaults.standard.stringArray(forKey: key) ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static func add(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(limit)), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

enum RecentQRCodes {
    private static let key = "recentQRCodes"
    private static let limit = 8

    static var texts: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ text: String) {
        var texts = texts
        texts.removeAll { $0 == text }
        texts.insert(text, at: 0)
        UserDefaults.standard.set(Array(texts.prefix(limit)), forKey: key)
    }
}
