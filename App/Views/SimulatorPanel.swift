import SwiftUI

struct SimulatorPanel: View {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Simulator").font(.headline)
                Spacer()
                if simulators.isBusy { ProgressView().controlSize(.small) }
                Button { Task { await simulators.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }

            Picker("Device", selection: $simulators.selectedUDID) {
                ForEach(simulators.devices) { device in
                    Text("\(device.name) · \(device.runtime)").tag(Optional(device.udid))
                }
            }
            .labelsHidden()
            .disabled(simulators.devices.isEmpty)

            Toggle("Inject into every app launched", isOn: Binding(
                get: { simulators.injectionEnabled },
                set: { value in Task { await simulators.setInjection(value) } }
            ))
            .disabled(simulators.selectedUDID == nil || !model.injectInstalled)
            .help("Stays on after the simulator restarts while SimCamLite is running")

            Toggle("Inject into every simulator as it boots", isOn: Binding(
                get: { simulators.injectsAllSimulators },
                set: { value in Task { await simulators.setInjectsAllSimulators(value) } }
            ))
            .disabled(!model.injectInstalled)
            .help("Also covers simulators never enabled before. Apps launched from Xcode pick it up too.")

            HStack {
                Text(simulators.xcodeEnvironment)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button { simulators.copyXcodeEnvironment() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .help("Copy for Xcode scheme › Run › Environment Variables")
            }

            Divider()

            Text("Connected apps").font(.subheadline.weight(.semibold))
            if model.clients.isEmpty {
                Text("No app is using SimCamLite").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.clients) { client in
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.processName).font(.callout.weight(.medium))
                    Text("\(client.bundleID) · pid \(client.pid)").font(.caption).foregroundStyle(.secondary)
                    Text("\(client.cameraDescription) · \(client.outputWidth)×\(client.outputHeight) · \(client.framesDelivered) frames · \(client.photoCount) photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Text("Apps").font(.subheadline.weight(.semibold))
                TextField("Filter", text: $appFilter).textFieldStyle(.roundedBorder).controlSize(.small)
            }
            List(filteredApps) { app in
                HStack {
                    VStack(alignment: .leading) {
                        Text(app.name)
                        Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Launch") { Task { await simulators.launch(app) } }
                        .controlSize(.small)
                        .disabled(!model.injectInstalled)
                }
            }
            .listStyle(.inset)

            if let message = simulators.message {
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .padding(16)
    }
}
