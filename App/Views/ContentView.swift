import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case camera, simulator, xcode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Camera"
        case .simulator: "Simulator"
        case .xcode: "Run from Xcode"
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera"
        case .simulator: "iphone"
        case .xcode: "hammer"
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var simulators: SimulatorModel
    @AppStorage("mainSection") private var section: MainSection = .camera

    init(model: AppModel) {
        self.model = model
        simulators = model.simulators
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<MainSection?>(get: { section }, set: { if let value = $0 { section = value } })) {
                ForEach(MainSection.allCases) { item in
                    sidebarRow(item).tag(item)
                }
                SidebarApps(model: model, simulators: simulators)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            switch section {
            case .camera: CameraView(model: model, simulators: simulators) { section = $0 }
            case .simulator: SimulatorView(model: model, simulators: simulators)
            case .xcode: XcodeSetupView(model: model, simulators: simulators)
            }
        }
        .navigationTitle("SimCamLite")
        .toolbar { toolbar }
        .modifier(HidesToolbarTitle())
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                Text(toast)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
        .onAppear { simulators.reloadXcodeProjects() }
    }

    /// Xcode-like: run control on the left, an activity capsule in the middle, stream settings on the right.
    /// Standard toolbar items, so macOS 26 renders them on Liquid Glass.
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                model.isStreaming ? model.stopStreaming() : model.startStreaming()
            } label: {
                Label(model.isStreaming ? "Stop" : "Start", systemImage: model.isStreaming ? "stop.fill" : "play.fill")
            }
            .help(model.isStreaming ? "Stop streaming to the simulator" : "Start streaming to the simulator")
        }
        ToolbarItem(placement: .navigation) {
            RunDestinationPicker(simulators: simulators)
        }
        ToolbarItem(placement: .navigation) {
            if simulators.isBusy {
                ProgressView().controlSize(.small).padding(.horizontal, 6)
            } else if let device = simulators.selectedDevice, !device.isBooted {
                Button {
                    Task { await simulators.boot(device.udid) }
                } label: {
                    Label("Boot", systemImage: "power")
                }
                .labelStyle(.titleAndIcon)
                .help("Boot \(device.name) and open Simulator")
            }
        }
        ToolbarItem(placement: .principal) {
            ActivityCapsule(model: model, simulators: simulators)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Frame rate", selection: $model.frameRate) {
                ForEach(FrameRate.allCases) { Text($0.title).tag($0) }
            }
            .help("Maximum rate sent to the simulator")
            Menu {
                Picker("Device profile", selection: $model.deviceProfile) {
                    ForEach(DeviceProfile.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(model.deviceProfile.shortTitle, systemImage: "camera.aperture")
            }
            .labelStyle(.titleAndIcon)
            .fixedSize()
            .help("Cameras the app sees. Applies to apps launched after the change.")
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: MainSection) -> some View {
        switch item {
        case .camera:
            Label(item.title, systemImage: item.symbol)
                .badge(model.clients.count)
        case .simulator:
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                    Text(simulators.selectedDevice?.name ?? "No simulator").font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: item.symbol)
            }
            .badge(simulators.bootedDevices.count)
        case .xcode:
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                    Text(simulators.isXcodeSetUp ? "\(simulators.xcodeProjects.count) project(s)" : "Not set up")
                        .font(.caption).foregroundStyle(simulators.isXcodeSetUp ? Color.secondary : .orange)
                }
            } icon: {
                Image(systemName: item.symbol)
            }
            .badge(simulators.isXcodeSetUp ? nil : Text(Image(systemName: "exclamationmark.triangle.fill")).foregroundColor(.orange))
        }
    }
}

/// Quick launch: apps on the selected simulator, started with SimCamLite in one click.
struct SidebarApps: View {
    @ObservedObject var model: AppModel
    @ObservedObject var simulators: SimulatorModel
    @State private var hovered: String?

    var body: some View {
        Section(simulators.selectedDevice.map { "Apps on \($0.name)" } ?? "Apps") {
            if let device = simulators.selectedDevice, !device.isBooted {
                Button {
                    Task { await simulators.boot(device.udid) }
                } label: {
                    Label("Boot to list apps", systemImage: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            } else if simulators.apps.isEmpty {
                Text("No apps installed").foregroundStyle(.secondary)
            }
            ForEach(simulators.selectedDevice?.isBooted == true ? simulators.apps : []) { app in
                Button {
                    launch(app)
                } label: {
                    HStack(spacing: 8) {
                        SimulatorAppIcon(app: app, size: 20)
                        Text(app.name).lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "play.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .opacity(hovered == app.id ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? app.id : (hovered == app.id ? nil : hovered) }
                .help("Launch \(app.name) with SimCamLite (\(app.bundleID))")
                .contextMenu {
                    Button("Launch with SimCamLite") { launch(app) }
                    Button("Copy Bundle ID") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(app.bundleID, forType: .string)
                    }
                }
            }
        }
    }

    private func launch(_ app: SimulatorApp) {
        Task {
            await simulators.launch(app)
            if let message = simulators.message { model.showToast(message) }
        }
    }
}

/// Mirrors Xcode's activity view: what is streaming, to which simulator, and who is using it.
struct ActivityCapsule: View {
    @ObservedObject var model: AppModel
    @ObservedObject var simulators: SimulatorModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(status).fontWeight(.medium)
            if !model.clients.isEmpty {
                Text("·").foregroundStyle(.tertiary)
                Text(model.clients.count == 1 ? model.clients[0].processName : "\(model.clients.count) apps")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 12)
        
        .help(model.injectInstalled ? InjectInstaller.loaderPath : (model.installError ?? "Inject library missing"))
    }

    private var status: String {
        if !model.sharedMemoryReady { return "Shared memory unavailable" }
        if !model.injectInstalled { return "Inject library missing" }
        return model.isStreaming ? "Streaming \(model.frameRate.title)" : "Stopped"
    }

    private var icon: String {
        if !model.sharedMemoryReady || !model.injectInstalled { return "exclamationmark.triangle.fill" }
        return model.isStreaming ? "dot.radiowaves.left.and.right" : "pause.circle"
    }

    private var color: Color {
        if !model.sharedMemoryReady || !model.injectInstalled { return .orange }
        return model.isStreaming ? .green : .secondary
    }
}

/// Xcode's run destination: the simulator SimCamLite targets, running ones first.
struct RunDestinationPicker: View {
    @ObservedObject var simulators: SimulatorModel

    var body: some View {
        Menu {
            let booted = simulators.bootedDevices
            if !booted.isEmpty {
                Section("Running") { ForEach(booted) { item($0) } }
            }
            Section("Available") { ForEach(simulators.devices.filter { !$0.isBooted }) { item($0) } }
            Divider()
            Button("Open Simulator") { simulators.openSimulatorApp() }
            Button("Refresh") { Task { await simulators.refresh() } }
        } label: {
            if let device = simulators.selectedDevice {
                Label {
                    Text(device.name) + Text("  \(device.runtime)").foregroundColor(.secondary)
                } icon: {
                    Image(systemName: Self.symbol(device))
                }
            } else {
                Label("No Simulator", systemImage: "iphone.slash")
            }
        }
        .labelStyle(.titleAndIcon)
        .fixedSize()
        .help(simulators.selectedDevice.map { "\($0.name) · \($0.runtime) · \($0.isBooted ? "Running" : "Shut down")" }
            ?? "No simulator found")
    }

    private func item(_ device: SimulatorDevice) -> some View {
        Button {
            simulators.selectedUDID = device.udid
        } label: {
            if device.udid == simulators.selectedUDID {
                Label("\(device.name) (\(device.runtime))", systemImage: "checkmark")
            } else {
                Label("\(device.name) (\(device.runtime))", systemImage: Self.symbol(device))
            }
        }
    }

    static func symbol(_ device: SimulatorDevice) -> String {
        device.name.hasPrefix("iPad") ? "ipad" : "iphone"
    }
}

/// Back and front sources plus the apps currently reading frames.
struct CameraView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var simulators: SimulatorModel
    let open: (MainSection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            banners
            Form {
                Section {
                    StreamPanel(stream: model.back, preview: model.backPreview)
                } header: {
                    Label("Back camera", systemImage: "camera")
                }

                Section {
                    Toggle("Same as back camera", isOn: $model.frontFollowsBack)
                    if model.frontFollowsBack {
                        HStack(alignment: .top, spacing: 16) {
                            PreviewImage(feed: model.frontPreview).frame(width: 200)
                            Text("The front camera shows the back camera's source. Turn this off to give it its own.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        StreamPanel(stream: model.front, preview: model.frontPreview)
                    }
                } header: {
                    Label("Front camera", systemImage: "arrow.triangle.2.circlepath.camera")
                }

                Section("Connected apps") {
                    if model.clients.isEmpty {
                        Text("No app is using SimCamLite yet. Launch one from Simulator, or Run it from Xcode once the project is set up.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.clients) { client in
                        HStack(spacing: 10) {
                            Image(systemName: "app.badge.checkmark").font(.title2).foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(client.processName).fontWeight(.medium)
                                Text("\(client.bundleID) · pid \(client.pid) · \(client.cameraDescription) · \(client.outputWidth)×\(client.outputHeight) · \(client.framesDelivered) frames · \(client.photoCount) photos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    /// Setup gaps that silently leave apps without the camera; shown until fixed.
    @ViewBuilder
    private var banners: some View {
        let device = simulators.selectedDevice
        VStack(spacing: 8) {
            if !model.injectInstalled {
                SetupBanner(symbol: "xmark.octagon.fill", tint: .red,
                            title: "SimCamLite loader isn't installed",
                            message: model.installError ?? "No app can receive camera frames until it is installed.") {
                    Button("Install") { model.installInject() }.buttonStyle(.borderedProminent).tint(.red)
                }
            }
            if !simulators.isXcodeSetUp {
                SetupBanner(symbol: "exclamationmark.triangle.fill", tint: .orange,
                            title: "Apps run from Xcode won't see this camera",
                            message: "Xcode Run replaces the simulator's injection, so debugging sessions get no camera until your project is set up. It takes one click per project.") {
                    Button { open(.xcode) } label: { Label("Set Up Xcode…", systemImage: "hammer") }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                }
            }
            if let device, device.isBooted, !simulators.injectionEnabled {
                SetupBanner(symbol: "info.circle.fill", tint: .blue,
                            title: "Injection is off on \(device.name)",
                            message: "Apps opened from the Home screen won't use SimCamLite. Turn it on, or launch apps from the Simulator section.") {
                    Button("Turn On") { Task { await simulators.setInjection(true, udid: device.udid) } }
                    Button("Simulator…") { open(.simulator) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

struct SetupBanner<Actions: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.callout).foregroundStyle(.secondary).lineLimit(3)
            }
            Spacer(minLength: 12)
            actions()
        }
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.3)))
    }
}

struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .foregroundStyle(.white)
            .padding(8)
    }
}

struct PreviewImage: View {
    @ObservedObject var feed: PreviewFeed

    var body: some View {
        ZStack {
            Rectangle().fill(.black)
            if let image = feed.image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}


/// The run destination stands in for the title, as in Xcode.
private struct HidesToolbarTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}
