import SwiftUI

/// Every simulator from Xcode's device list, injection for the selected one, and its apps.
struct SimulatorView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var simulators: SimulatorModel
    @State private var appFilter = ""

    private var filteredApps: [SimulatorApp] {
        guard !appFilter.isEmpty else { return simulators.apps }
        return simulators.apps.filter {
            $0.name.localizedCaseInsensitiveContains(appFilter) || $0.bundleID.localizedCaseInsensitiveContains(appFilter)
        }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: deviceSymbol)
                        .font(.system(size: 28))
                        .foregroundStyle(simulators.selectedDevice?.isBooted == true ? Color.accentColor : .secondary)
                        .frame(width: 36)
                    Picker("Simulator", selection: $simulators.selectedUDID) {
                        let booted = simulators.bootedDevices
                        if !booted.isEmpty {
                            Section("Running") {
                                ForEach(booted) { Text("\($0.name) · \($0.runtime)").tag(Optional($0.udid)) }
                            }
                        }
                        Section("Available") {
                            ForEach(simulators.devices.filter { !$0.isBooted }) {
                                Text("\($0.name) · \($0.runtime)").tag(Optional($0.udid))
                            }
                        }
                    }
                    .disabled(simulators.devices.isEmpty)
                    if simulators.isBusy { ProgressView().controlSize(.small) }
                }
                if let device = simulators.selectedDevice {
                    LabeledContent("Status") {
                        if device.isBooted {
                            Label("Running", systemImage: "circle.fill").foregroundStyle(.green).labelStyle(DotLabelStyle())
                        } else {
                            HStack {
                                Label("Shut down", systemImage: "circle.fill").foregroundStyle(.secondary).labelStyle(DotLabelStyle())
                                Button("Boot") { Task { await simulators.boot() } }
                                    .disabled(simulators.isBusy)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Device")
                    Spacer()
                    Button { Task { await simulators.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .help("Reload simulators")
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { simulators.injectionEnabled },
                    set: { value in Task { await simulators.setInjection(value) } }
                )) {
                    Text("Use SimCamLite in every app on this simulator")
                    Text("Kept after the simulator restarts, while SimCamLite is running.")
                }
                .disabled(simulators.selectedUDID == nil || !model.injectInstalled)
                Toggle(isOn: Binding(
                    get: { simulators.injectsAllSimulators },
                    set: { value in Task { await simulators.setInjectsAllSimulators(value) } }
                )) {
                    Text("Every simulator as it boots")
                    Text("Apps run from Xcode need the project set up once: see Run from Xcode.")
                }
                .disabled(!model.injectInstalled)
            } header: {
                Text("Camera injection")
            }

            Section {
                if simulators.selectedDevice?.isBooted != true {
                    Text("Boot the simulator to see its apps.").foregroundStyle(.secondary)
                } else if simulators.apps.isEmpty {
                    Text("No apps installed. Build and run your app from Xcode once.").foregroundStyle(.secondary)
                } else {
                    TextField("Filter", text: $appFilter, prompt: Text("Filter apps"))
                    ForEach(filteredApps) { app in
                        HStack(spacing: 10) {
                            SimulatorAppIcon(app: app, size: 32)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Launch") { Task { await simulators.launch(app) } }
                                .disabled(!model.injectInstalled)
                                .help("Relaunch with SimCamLite (without the Xcode debugger)")
                        }
                    }
                }
            } header: {
                Text("Apps")
            }

            if let message = simulators.message {
                Section { Text(message).font(.callout).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    private var deviceSymbol: String {
        simulators.selectedDevice?.name.hasPrefix("iPad") == true ? "ipad" : "iphone"
    }
}

struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon.font(.system(size: 7))
            configuration.title.foregroundStyle(.primary)
        }
    }
}

/// The app's home-screen icon, read from the installed simulator bundle (falls back to a generic icon).
struct SimulatorAppIcon: View {
    let app: SimulatorApp
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "app.fill").resizable().foregroundStyle(.quaternary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        .task(id: app.bundleURL) { image = await AppIconLoader.icon(for: app) }
    }
}

@MainActor
enum AppIconLoader {
    private static var cache: [URL: NSImage] = [:]

    static func icon(for app: SimulatorApp) async -> NSImage? {
        guard let bundle = app.bundleURL else { return nil }
        if let cached = cache[bundle] { return cached }
        let image = await Task.detached(priority: .utility) { load(bundle) }.value
        if let image { cache[bundle] = image }
        return image
    }

    private nonisolated static func load(_ bundle: URL) -> NSImage? {
        guard let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Info.plist")) as? [String: Any] else { return nil }
        var names: [String] = []
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            let icons = (info[key] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
            names += (icons?["CFBundleIconFiles"] as? [String] ?? []).reversed()
        }
        for name in names {
            for suffix in ["@3x.png", "@2x.png", "@2x~ipad.png", ".png"] {
                let url = bundle.appendingPathComponent(name + suffix)
                if let image = NSImage(contentsOf: url), image.isValid { return image }
            }
        }
        return nil
    }
}
