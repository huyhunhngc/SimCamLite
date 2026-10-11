import SwiftUI
import UniformTypeIdentifiers

/// Step-by-step setup so apps run from Xcode (with the debugger) get the SimCamLite camera.
struct XcodeSetupView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var simulators: SimulatorModel
    @State private var dropTargeted = false
    private let xcode = XcodeApp.current

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    FlowIcon(image: xcode?.icon, symbol: "hammer.fill", caption: "Xcode ▶ Run")
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    FlowIcon(image: nil, symbol: "doc.badge.gearshape", caption: "Scheme env")
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    FlowIcon(image: NSApp.applicationIconImage, symbol: "camera", caption: "SimCamLite camera")
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    FlowIcon(image: nil, symbol: "iphone", caption: "App + debugger")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                Text("Xcode Run starts your app with its own \(XcodeSchemeSetup.variable), which hides the simulator-wide injection. Setting up a project adds the SimCamLite loader to the Run environment of its iOS app schemes once — then just press Run.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Checklist") {
                StepRow(number: 1, done: xcode != nil, image: xcode?.icon, symbol: "hammer",
                        title: xcode.map { "Xcode \($0.version)" } ?? "Xcode not found",
                        detail: xcode?.url.path ?? "Install Xcode to run apps on the simulator.") { EmptyView() }
                StepRow(number: 2, done: model.injectInstalled, image: nil, symbol: "shippingbox",
                        title: model.injectInstalled ? "SimCamLite loader installed" : "SimCamLite loader missing",
                        detail: model.installError ?? InjectInstaller.loaderPath) {
                    if !model.injectInstalled { Button("Install") { model.installInject() } }
                }
                StepRow(number: 3, done: hasEnabledScheme, image: nil, symbol: "folder.badge.gearshape",
                        title: hasEnabledScheme ? "Project set up" : "Set up your project",
                        detail: "Choose or drop an .xcodeproj / .xcworkspace. Only iOS app schemes are changed.") {
                    Button("Set Up Project…") { simulators.setUpXcodeProject() }
                        .buttonStyle(.borderedProminent)
                }
                StepRow(number: 4, done: hasEnabledScheme && !model.clients.isEmpty, image: nil, symbol: "play.fill",
                        title: "Stop and Run again in Xcode",
                        detail: model.clients.isEmpty
                            ? "The app appears under Camera › Connected apps once it opens the camera."
                            : "Connected: \(model.clients.map(\.processName).joined(separator: ", "))") { EmptyView() }
            }

            ForEach(simulators.xcodeProjects, id: \.self) { path in
                ProjectSection(path: path, schemes: simulators.xcodeSchemes[path] ?? [], simulators: simulators)
            }

            Section {
                DisclosureGroup("Set up a scheme by hand") {
                    Text("Edit Scheme › Run › Arguments › Environment Variables, add (iOS schemes only — a macOS app would fail to launch):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(simulators.xcodeEnvironment)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button { simulators.copyXcodeEnvironment() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    }
                    Text("Command line: simcam xcode setup|remove|status [path]")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if let message = simulators.message {
                Section { Text(message).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8]))
                    .overlay(Text("Drop to set up").font(.title3.weight(.semibold)).padding(10)
                        .background(.regularMaterial, in: Capsule()))
                    .padding(8)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in simulators.setUpXcodeProject(at: url) }
            }
            return true
        }
        .onAppear { simulators.reloadXcodeProjects() }
    }

    private var hasEnabledScheme: Bool { simulators.isXcodeSetUp }
}

private struct ProjectSection: View {
    let path: String
    let schemes: [XcodeSchemeSetup.Scheme]
    @ObservedObject var simulators: SimulatorModel

    var body: some View {
        Section {
            if schemes.isEmpty {
                Text("No schemes found. The project may have moved.").foregroundStyle(.secondary)
            }
            ForEach(schemes) { scheme in
                Toggle(isOn: Binding(
                    get: { scheme.isEnabled },
                    set: { simulators.setScheme(scheme, enabled: $0, project: path) }
                )) {
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: scheme))
                            .foregroundStyle(scheme.isEnabled ? Color.accentColor : .secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(scheme.name)
                            Text(detail(for: scheme)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(isBlocked(scheme) && !scheme.isEnabled)
            }
        } header: {
            HStack(spacing: 8) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 20, height: 20)
                Text(URL(fileURLWithPath: path).lastPathComponent)
                Spacer()
                Button { NSWorkspace.shared.open(URL(fileURLWithPath: path)) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.borderless)
                    .help("Open in Xcode")
                Button { simulators.removeXcodeProject(path) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                    .help("Remove SimCamLite from every scheme of this project")
            }
        } footer: {
            Text(path).font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
        }
    }

    /// macOS, Catalyst and non-app schemes would break or have nothing to inject into.
    private func isBlocked(_ scheme: XcodeSchemeSetup.Scheme) -> Bool {
        guard let reason = scheme.skipReason else { return false }
        return !reason.hasPrefix("platform unknown")
    }

    private func icon(for scheme: XcodeSchemeSetup.Scheme) -> String {
        guard let reason = scheme.skipReason else { return "iphone" }
        if reason.contains("macosx") || reason.contains("Catalyst") { return "macbook" }
        return isBlocked(scheme) ? "minus.circle" : "questionmark.circle"
    }

    private func detail(for scheme: XcodeSchemeSetup.Scheme) -> String {
        let kind = scheme.isShared ? "Shared scheme" : "User scheme"
        guard let reason = scheme.skipReason else { return "\(kind) · iOS app" }
        return "\(kind) · \(isBlocked(scheme) ? "skipped: " : "")\(reason)"
    }
}

private struct StepRow<Accessory: View>: View {
    let number: Int
    let done: Bool
    let image: NSImage?
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        Image(nsImage: image).resizable()
                    } else {
                        Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 30, height: 30)
                Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.white, done ? .green : .orange)
                    .offset(x: 4, y: 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
            Spacer()
            accessory()
        }
        .padding(.vertical, 2)
    }
}

private struct FlowIcon: View {
    let image: NSImage?
    let symbol: String
    let caption: String

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(nsImage: image).resizable()
                } else {
                    Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 40, height: 40)
            Text(caption).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 84)
    }
}

struct XcodeApp {
    let url: URL
    let version: String
    let icon: NSImage

    static let current: XcodeApp? = {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.dt.Xcode") else { return nil }
        let version = Bundle(url: url)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        return XcodeApp(url: url, version: version, icon: NSWorkspace.shared.icon(forFile: url.path))
    }()
}
