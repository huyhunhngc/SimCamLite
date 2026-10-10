import AppKit

@MainActor
final class CLIInstaller: ObservableObject {
    enum Status: Equatable {
        case notInstalled
        case installed(String)
        case stale(String, target: String)
    }

    static let shared = CLIInstaller()
    static let systemPath = "/usr/local/bin/simcam"
    static let userPath = NSHomeDirectory() + "/.local/bin/simcam"
    private static let searchPaths = [systemPath, "/opt/homebrew/bin/simcam", userPath]

    @Published private(set) var status: Status = .notInstalled

    private init() {
        refresh()
    }

    var binaryPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/simcam").path
    }

    var isStale: Bool {
        if case .stale = status { return true }
        return false
    }

    var menuTitle: String {
        isStale ? "Fix Command Line Tool… ⚠︎" : "Install Command Line Tool…"
    }

    func refresh() {
        let fm = FileManager.default
        let ours = URL(fileURLWithPath: binaryPath).resolvingSymlinksInPath().path
        var found: Status = .notInstalled
        for path in Self.searchPaths {
            guard let target = try? fm.destinationOfSymbolicLink(atPath: path) else { continue }
            if URL(fileURLWithPath: path).resolvingSymlinksInPath().path == ours {
                if found == .notInstalled { found = .installed(path) }
            } else if target.hasSuffix(".app/Contents/MacOS/simcam") {
                found = .stale(path, target: target)
                break
            }
        }
        if status != found {
            status = found
        }
    }

    func installInteractively() {
        NSApp.activate(ignoringOtherApps: true)
        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            showAlert("simcam is missing", "The command line tool was not found in \(binaryPath).")
            return
        }
        if case .stale(let path, let target) = status {
            let alert = NSAlert()
            alert.messageText = "Update simcam?"
            alert.informativeText = "\(path) points to an old location:\n\(target)\n\nUpdate it to this copy of SimCamLite?"
            alert.addButton(withTitle: "Update")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        if (try? linkDirectly(Self.systemPath)) != nil || linkWithAdmin(Self.systemPath) {
            refresh()
            removeStale()
            showAlert("simcam installed", "Open a new terminal window and run `simcam status`.")
            return
        }
        do {
            try linkDirectly(Self.userPath)
            refresh()
            removeStale()
            let command = #"echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc"#
            let alert = NSAlert()
            alert.messageText = "simcam installed in ~/.local/bin"
            alert.informativeText = "If `simcam` isn't found in a new terminal, add ~/.local/bin to your PATH:\n\n\(command)"
            alert.addButton(withTitle: "Copy Command")
            alert.addButton(withTitle: "OK")
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
            }
        } catch {
            refresh()
            showAlert("Could not install simcam", error.localizedDescription)
        }
    }

    private func linkDirectly(_ path: String) throws {
        let fm = FileManager.default
        let directory = (path as NSString).deletingLastPathComponent
        if directory != (Self.systemPath as NSString).deletingLastPathComponent {
            try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        guard fm.isWritableFile(atPath: directory) else { throw CocoaError(.fileWriteNoPermission) }
        if (try? fm.destinationOfSymbolicLink(atPath: path)) != nil || fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
        try fm.createSymbolicLink(atPath: path, withDestinationPath: binaryPath)
    }

    private func linkWithAdmin(_ path: String) -> Bool {
        let directory = (path as NSString).deletingLastPathComponent
        let shell = "mkdir -p \(quoted(directory)) && ln -sfn \(quoted(binaryPath)) \(quoted(path))"
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = NSAppleScript(source: "do shell script \"\(escaped)\" with prompt \"SimCamLite wants to install the simcam command line tool.\" with administrator privileges")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        return error == nil && script != nil
    }

    private func removeStale() {
        guard case .stale(let stalePath, _) = status else { return }
        try? FileManager.default.removeItem(atPath: stalePath)
        refresh()
    }

    private func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
