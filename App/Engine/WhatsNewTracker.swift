import Foundation

/// Shows the bundled release notes once after the app is updated to a new version.
@MainActor
final class WhatsNewTracker: ObservableObject {
    private static let lastSeenKey = "whatsNew.lastSeenVersion"

    @Published var isPresented = false
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// A fresh install only records the version; an update to a newer version presents the sheet.
    func checkOnLaunch() {
        defer { defaults.set(version, forKey: Self.lastSeenKey) }
        guard let lastSeen = defaults.string(forKey: Self.lastSeenKey), !notes.isEmpty else { return }
        isPresented = version.compare(lastSeen, options: .numeric) == .orderedDescending
    }

    func show() {
        isPresented = true
    }

    /// The body of RELEASE_NOTES.md, without its `# SimCam Lite <version>` title line.
    var notes: String {
        guard let url = Bundle.main.url(forResource: "RELEASE_NOTES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        var lines = text.components(separatedBy: .newlines)
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].hasPrefix("# ") {
            lines.remove(at: first)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
