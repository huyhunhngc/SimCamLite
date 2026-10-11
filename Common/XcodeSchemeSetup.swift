import Foundation

/// One-click setup so apps run from Xcode load SimCamLite while keeping the debugger.
///
/// Xcode Run sets its own `DYLD_INSERT_LIBRARIES` (Main Thread Checker, log redirect, ...), which hides the
/// simulator-wide `launchctl setenv` value. A value in the scheme's Run environment is kept and Xcode appends its own
/// libraries to it. Only schemes that run an iOS app are changed: a macOS process aborts when asked to insert the
/// simulator loader, while a missing loader (machine without SimCamLite) is skipped by the simulator's dyld.
enum XcodeSchemeSetup {
    static let variable = "DYLD_INSERT_LIBRARIES"
    private static let projectsKey = "xcode.projects"

    struct Scheme: Identifiable, Hashable {
        let name: String
        let url: URL
        let isShared: Bool
        /// Why the scheme is left alone; nil when it runs an iOS app.
        let skipReason: String?
        let isEnabled: Bool
        var id: String { url.path }
    }

    struct SetupError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    // MARK: Remembered projects (shown in the GUI)

    static var projects: [String] {
        InjectionPreferences.defaults.stringArray(forKey: projectsKey) ?? []
    }

    static func remember(_ container: URL, _ remembered: Bool) {
        var paths = projects.filter { $0 != container.path }
        if remembered { paths.append(container.path) }
        InjectionPreferences.defaults.set(paths, forKey: projectsKey)
        InjectionPreferences.defaults.synchronize()
    }

    // MARK: Finding schemes

    static func isContainer(_ url: URL) -> Bool {
        ["xcodeproj", "xcworkspace"].contains(url.pathExtension)
    }

    /// The workspace (preferred, e.g. CocoaPods) or project in a directory.
    static func container(in directory: URL) throws -> URL {
        if isContainer(directory) { return directory }
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let workspaces = items.filter { $0.pathExtension == "xcworkspace" }
        let projects = items.filter { $0.pathExtension == "xcodeproj" }
        if workspaces.count == 1 { return workspaces[0] }
        if workspaces.isEmpty, projects.count == 1 { return projects[0] }
        if workspaces.isEmpty, projects.isEmpty {
            throw SetupError("No .xcodeproj or .xcworkspace in \(directory.path)")
        }
        throw SetupError("Several Xcode projects in \(directory.path); pass one of: "
            + (workspaces + projects).map(\.lastPathComponent).joined(separator: ", "))
    }

    static func schemes(in container: URL) throws -> [Scheme] {
        guard isContainer(container), FileManager.default.fileExists(atPath: container.path) else {
            throw SetupError("Not an Xcode project or workspace: \(container.path)")
        }
        var containers = [container]
        if container.pathExtension == "xcworkspace" { containers += projects(inWorkspace: container) }
        var schemes: [Scheme] = []
        var seen: Set<String> = []
        for owner in containers {
            for (url, shared) in schemeFiles(in: owner) where seen.insert(url.path).inserted {
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                schemes.append(Scheme(
                    name: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    isShared: shared,
                    skipReason: skipReason(text, owner: owner),
                    isEnabled: isEnabled(text)
                ))
            }
        }
        if schemes.isEmpty {
            throw SetupError("""
                No scheme files in \(container.lastPathComponent). In Xcode open Product › Scheme › Manage Schemes… \
                (this saves the auto-created schemes), then try again.
                """)
        }
        return schemes.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func schemeFiles(in container: URL) -> [(URL, Bool)] {
        let fm = FileManager.default
        var directories = [(container.appendingPathComponent("xcshareddata/xcschemes"), true)]
        let userData = container.appendingPathComponent("xcuserdata")
        for user in (try? fm.contentsOfDirectory(at: userData, includingPropertiesForKeys: nil)) ?? [] {
            directories.append((user.appendingPathComponent("xcschemes"), false))
        }
        return directories.flatMap { directory, shared in
            ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "xcscheme" }
                .map { ($0, shared) }
        }
    }

    private static func projects(inWorkspace workspace: URL) -> [URL] {
        guard let text = try? String(contentsOf: workspace.appendingPathComponent("contents.xcworkspacedata"), encoding: .utf8) else { return [] }
        let base = workspace.deletingLastPathComponent()
        return matches(#"location\s*=\s*"(?:group|container):([^"]+\.xcodeproj)""#, in: text)
            .map { base.appendingPathComponent($0).standardizedFileURL }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    // MARK: Changing schemes

    /// Adds (or removes) the loader in the Run environment of every scheme that runs an iOS app; returns the
    /// schemes that changed. With `force`, schemes whose platform is unknown are changed as well.
    @discardableResult
    static func setEnabled(_ enabled: Bool, in container: URL, schemeNames: [String] = [], force: Bool = false) throws -> [Scheme] {
        var targets = try schemes(in: container)
        if !schemeNames.isEmpty {
            let missing = schemeNames.filter { name in !targets.contains { $0.name == name } }
            if !missing.isEmpty { throw SetupError("No scheme named \(missing.joined(separator: ", ")) in \(container.lastPathComponent)") }
            targets = targets.filter { schemeNames.contains($0.name) }
        }
        var changed: [Scheme] = []
        for scheme in targets where scheme.isEnabled != enabled {
            if enabled, let reason = scheme.skipReason, !(force && reason.hasPrefix(unknownPlatform)) { continue }
            let text = try String(contentsOf: scheme.url, encoding: .utf8)
            guard let updated = enabled ? enable(text) : disable(text), updated != text else { continue }
            try updated.write(to: scheme.url, atomically: true, encoding: .utf8)
            changed.append(scheme)
        }
        let stillEnabled = try schemes(in: container).contains(where: \.isEnabled)
        remember(container, stillEnabled)
        return changed
    }

    private static var loader: String { InjectInstaller.loaderPath }

    static func isEnabled(_ scheme: String) -> Bool {
        guard let launch = launchAction(in: scheme), let element = variableElement(in: scheme, launch: launch) else { return false }
        let text = String(scheme[element])
        return attribute("value", in: text)?.components(separatedBy: ":").contains(loader) == true
            && attribute("isEnabled", in: text) != "NO"
    }

    private static func enable(_ scheme: String) -> String? {
        guard let launch = launchAction(in: scheme) else { return nil }
        var text = scheme
        if let element = variableElement(in: text, launch: launch) {
            var entry = String(text[element])
            let current = (attribute("value", in: entry) ?? "").components(separatedBy: ":").filter { !$0.isEmpty && $0 != loader }
            entry = setAttribute("value", to: ([loader] + current).joined(separator: ":"), in: entry)
            entry = setAttribute("isEnabled", to: "YES", in: entry)
            text.replaceSubrange(element, with: entry)
            return text
        }
        let entry = """
                     <EnvironmentVariable
                        key = "\(variable)"
                        value = "\(loader)"
                        isEnabled = "YES">
                     </EnvironmentVariable>

            """
        if let list = text.range(of: "<EnvironmentVariables>", range: launch),
           let lineEnd = text[list.upperBound...].firstIndex(of: "\n") {
            text.insert(contentsOf: entry, at: text.index(after: lineEnd))
            return text
        }
        guard let close = text.range(of: "</LaunchAction>", range: launch) else { return nil }
        let lineStart = text[..<close.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? close.lowerBound
        text.insert(contentsOf: "      <EnvironmentVariables>\n" + entry + "      </EnvironmentVariables>\n", at: lineStart)
        return text
    }

    private static func disable(_ scheme: String) -> String? {
        guard let launch = launchAction(in: scheme), let element = variableElement(in: scheme, launch: launch) else { return nil }
        var text = scheme
        let entry = String(text[element])
        let rest = (attribute("value", in: entry) ?? "").components(separatedBy: ":").filter { !$0.isEmpty && $0 != loader }
        if !rest.isEmpty {
            text.replaceSubrange(element, with: setAttribute("value", to: rest.joined(separator: ":"), in: entry))
            return text
        }
        text.removeSubrange(element)
        if let launch = launchAction(in: text),
           let empty = text.range(of: #"[ \t]*<EnvironmentVariables>\s*</EnvironmentVariables>[ \t]*\n?"#, options: .regularExpression, range: launch) {
            text.removeSubrange(empty)
        }
        return text
    }

    // MARK: Scheme parsing

    private static let unknownPlatform = "platform unknown"

    private static func skipReason(_ scheme: String, owner: URL) -> String? {
        let base = owner.deletingLastPathComponent()
        guard let launch = launchAction(in: scheme),
              let runnable = scheme.range(of: #"<BuildableProductRunnable[\s\S]*?</BuildableProductRunnable>"#, options: .regularExpression, range: launch)
        else { return "does not run an app" }
        let block = String(scheme[runnable])
        guard let blueprint = attribute("BlueprintIdentifier", in: block),
              let container = attribute("ReferencedContainer", in: block), container.hasPrefix("container:")
        else { return "does not run an app" }
        var project = base.appendingPathComponent(String(container.dropFirst("container:".count)))
        guard project.pathExtension == "xcodeproj" else { return "not an Xcode project target" }
        if !FileManager.default.fileExists(atPath: project.path), owner.pathExtension == "xcodeproj" { project = owner }
        return platformSkipReason(target: blueprint, project: project)
    }

    /// nil when the target builds only for iOS; reads SDKROOT / SUPPORTED_PLATFORMS from the target and project.
    private static func platformSkipReason(target: String, project: URL) -> String? {
        guard let data = try? Data(contentsOf: project.appendingPathComponent("project.pbxproj")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let objects = plist["objects"] as? [String: [String: Any]],
              let targetObject = objects[target]
        else { return "\(unknownPlatform) (target not found)" }

        func settings(_ owner: [String: Any]?) -> [[String: Any]] {
            guard let listID = owner?["buildConfigurationList"] as? String,
                  let configIDs = objects[listID]?["buildConfigurations"] as? [String] else { return [] }
            return configIDs.compactMap { objects[$0]?["buildSettings"] as? [String: Any] }
        }
        let rootID = plist["rootObject"] as? String
        let projectSettings = settings(rootID.flatMap { objects[$0] }).first ?? [:]
        let targetSettings = settings(targetObject)
        func values(_ key: String) -> [String] {
            (targetSettings.isEmpty ? [[:]] : targetSettings).compactMap { ($0[key] ?? projectSettings[key]) as? String }
        }

        if values("SUPPORTS_MACCATALYST").contains("YES") { return "also builds for Mac Catalyst" }
        let iOS: Set<String> = ["iphoneos", "iphonesimulator"]
        let supported = values("SUPPORTED_PLATFORMS").flatMap { $0.split(separator: " ").map(String.init) }
        if !supported.isEmpty {
            return Set(supported).isSubset(of: iOS) ? nil : "runs on \(Set(supported).subtracting(iOS).sorted().joined(separator: ", "))"
        }
        let sdks = values("SDKROOT")
        guard !sdks.isEmpty else { return "\(unknownPlatform) (SDKROOT not in the project file)" }
        return sdks.allSatisfy { $0.hasPrefix("iphone") } ? nil : "runs on \(Set(sdks).sorted().joined(separator: ", "))"
    }

    private static func launchAction(in scheme: String) -> Range<String.Index>? {
        scheme.range(of: #"<LaunchAction[\s\S]*?</LaunchAction>"#, options: .regularExpression)
    }

    private static func variableElement(in scheme: String, launch: Range<String.Index>) -> Range<String.Index>? {
        let pattern = #"[ \t]*<EnvironmentVariable\s[^>]*?key\s*=\s*"DYLD_INSERT_LIBRARIES"[^>]*?(?:/>|>\s*</EnvironmentVariable>)[ \t]*\n?"#
        return scheme.range(of: pattern, options: .regularExpression, range: launch)
    }

    private static func attribute(_ name: String, in element: String) -> String? {
        matches(#"\b\#(name)\s*=\s*"([^"]*)""#, in: element).first
    }

    private static func setAttribute(_ name: String, to value: String, in element: String) -> String {
        if let range = element.range(of: #"\b\#(name)\s*=\s*"[^"]*""#, options: .regularExpression) {
            return element.replacingCharacters(in: range, with: "\(name) = \"\(value)\"")
        }
        return element
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
