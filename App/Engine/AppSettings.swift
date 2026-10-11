import Foundation

/// Options restored when SimCamLite opens again. Stored as JSON in the app's defaults domain.
struct AppSettings: Codable {
    struct Stream: Codable {
        var source: SourceSpec = .pattern
        var options = RenderOptions()
    }

    var frameRate = FrameRate.fps30.rawValue
    var deviceProfile = DeviceProfile.triple.name
    var frontFollowsBack = true
    var back = Stream()
    var front = Stream()
    var selectedUDID: String?

    private static let key = "settings.v1"

    static func load() -> AppSettings? {
        guard let data = InjectionPreferences.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        InjectionPreferences.defaults.set(data, forKey: Self.key)
    }
}
