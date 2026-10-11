import SwiftUI

/// App-level settings: software updates and the `simcam` command line tool.
struct SettingsView: View {
    @ObservedObject var updates: UpdateCoordinator
    @ObservedObject var whatsNew: WhatsNewTracker
    @ObservedObject private var cli = CLIInstaller.shared

    var body: some View {
        Form {
            Section("Updates") {
                LabeledContent("Version") {
                    Text(versionText).textSelection(.enabled)
                }
                if updates.updateAvailable {
                    LabeledContent {
                        Button("Update to \(updates.latestVersion)…") { updates.checkForUpdates() }
                            .buttonStyle(.borderedProminent)
                    } label: {
                        Label("SimCam Lite \(updates.latestVersion) is available", systemImage: "arrow.down.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticallyChecksForUpdates($0) }
                ))
                .disabled(!updates.isEnabled)
                LabeledContent {
                    HStack {
                        Button("What's New…") { whatsNew.show() }
                            .disabled(whatsNew.notes.isEmpty)
                        Button("Check for Updates…") { updates.checkForUpdates() }
                            .disabled(!updates.canCheckForUpdates)
                    }
                } label: {
                    Text(lastCheckText).foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent {
                    switch cli.status {
                    case .installed:
                        Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .stale:
                        Button("Fix…") { cli.installInteractively() }.buttonStyle(.borderedProminent).tint(.orange)
                    case .notInstalled:
                        Button("Install…") { cli.installInteractively() }.buttonStyle(.borderedProminent)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("simcam")
                        Text(cliDetail).font(.caption).foregroundStyle(cli.isStale ? Color.orange : .secondary)
                    }
                }
                if case .installed = cli.status {
                    LabeledContent("Reinstall or move the link") {
                        Button("Install Again…") { cli.installInteractively() }
                    }
                }
                LabeledContent("Try it") {
                    Text("simcam status · simcam source ~/photo.png · simcam start")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Command Line Tool")
            } footer: {
                Text("simcam controls the running app from Terminal and scripts: start or stop streaming, switch sources and launch simulator apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { cli.refresh() }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var lastCheckText: String {
        guard updates.isEnabled else { return "Updates are not configured in this build" }
        guard let date = updates.lastUpdateCheckDate else { return "Never checked" }
        return "Last checked \(date.formatted(.relative(presentation: .named)))"
    }

    private var cliDetail: String {
        switch cli.status {
        case .installed(let path) where path == CLIInstaller.userPath: "Linked in ~/.local/bin. Make sure it is on your PATH."
        case .installed(let path): "Linked at \(path)"
        case .stale(let path, _): "\(path) points to an old copy of SimCamLite."
        case .notInstalled: "Links simcam into /usr/local/bin."
        }
    }
}
