import Foundation

/// Which simulators get `DYLD_INSERT_LIBRARIES` re-applied when they boot. `launchctl setenv` is lost on shutdown, so
/// SimCamLite.app re-applies it while running. Stored in the app's defaults domain so `simcam` and the GUI share it.
enum InjectionPreferences {
    private static let rememberedKey = "injection.rememberedUDIDs"
    private static let allSimulatorsKey = "injection.allSimulators"

    static var defaults: UserDefaults {
        if Bundle.main.bundleIdentifier == ControlPaths.appBundleID { return .standard }
        return UserDefaults(suiteName: ControlPaths.appBundleID) ?? .standard
    }

    /// Inject into every booted simulator, including ones never toggled before.
    static var injectsAllSimulators: Bool {
        get { defaults.bool(forKey: allSimulatorsKey) }
        set {
            defaults.set(newValue, forKey: allSimulatorsKey)
            defaults.synchronize()
        }
    }

    static var rememberedUDIDs: Set<String> {
        Set(defaults.stringArray(forKey: rememberedKey) ?? [])
    }

    static func isRemembered(_ udid: String) -> Bool { rememberedUDIDs.contains(udid) }

    static func shouldInject(_ udid: String) -> Bool { injectsAllSimulators || isRemembered(udid) }

    static func remember(_ enabled: Bool, udid: String) {
        var udids = rememberedUDIDs
        if enabled { udids.insert(udid) } else { udids.remove(udid) }
        defaults.set(udids.sorted(), forKey: rememberedKey)
        defaults.synchronize()
    }
}
