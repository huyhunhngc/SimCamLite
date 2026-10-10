import AVFoundation
import SwiftUI

struct PermissionsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var permissions: PermissionsModel
    @ObservedObject var simulators: SimulatorModel
    @ObservedObject private var cli = CLIInstaller.shared
    var onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SimCamLite").font(.system(size: 20, weight: .semibold))
                Text("Grant access and check the setup so iOS Simulator apps can use SimCamLite as their camera.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                SetupRow(
                    symbol: "web.camera",
                    title: "Camera",
                    detail: cameraDetail,
                    state: cameraState,
                    actionTitle: permissions.cameraBlocked ? "OPEN SYSTEM SETTINGS" : "ALLOW ACCESS",
                    action: { Task { await permissions.requestCamera() } }
                )
                SetupRow(
                    symbol: "hammer",
                    title: "Xcode Simulator tools",
                    detail: simulators.toolsAvailable == false
                        ? "xcrun simctl is unavailable. Install Xcode and run xcode-select."
                        : "Used to list simulators, enable injection and launch apps.",
                    state: simulators.toolsAvailable == true ? .done : (simulators.toolsAvailable == nil ? .checking : .required),
                    actionTitle: "CHECK AGAIN",
                    action: { Task { await simulators.refresh() } }
                )
                SetupRow(
                    symbol: "shippingbox",
                    title: "Inject library",
                    detail: model.installError ?? "Installed in /Users/Shared/SimCamLite so simulator apps can load it.",
                    state: model.injectInstalled ? .done : .required,
                    actionTitle: "INSTALL",
                    action: { model.installInject() }
                )
                SetupRow(
                    symbol: "terminal",
                    title: "Command line tool",
                    detail: cliDetail,
                    state: cliState,
                    actionTitle: cli.isStale ? "FIX" : "INSTALL",
                    action: { cli.installInteractively() }
                )
                SetupRow(
                    symbol: "iphone",
                    title: "Booted simulator",
                    detail: simulators.devices.isEmpty
                        ? "Boot a simulator, then launch your app from the SimCamLite menu."
                        : simulators.devices.map(\.name).joined(separator: ", "),
                    state: simulators.devices.isEmpty ? .optional : .done,
                    actionTitle: "OPEN SIMULATOR",
                    action: {
                        simulators.openSimulatorApp()
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            await simulators.refresh()
                        }
                    }
                )
            }

            HStack {
                Text("Camera access is only needed for the Mac camera source.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
        .onAppear {
            permissions.refresh()
            cli.refresh()
            Task { await simulators.refresh() }
        }
    }

    private var cliState: SetupRow.State {
        switch cli.status {
        case .installed: .done
        case .stale: .required
        case .notInstalled: .optional
        }
    }

    private var cliDetail: String {
        switch cli.status {
        case .installed(let path) where path == CLIInstaller.userPath: "simcam is linked in ~/.local/bin. Make sure it is on your PATH."
        case .installed(let path): "simcam is available in \((path as NSString).deletingLastPathComponent)."
        case .stale(let path, _): "\(path) points to an old copy of SimCamLite."
        case .notInstalled: "Links simcam into /usr/local/bin to control SimCamLite from Terminal."
        }
    }

    private var cameraState: SetupRow.State {
        switch permissions.camera {
        case .authorized: .done
        case .notDetermined: .optional
        default: .required
        }
    }

    private var cameraDetail: String {
        switch permissions.camera {
        case .authorized: "Mac cameras, iPhone Continuity Camera and virtual cameras can be used as sources."
        case .notDetermined: "Needed to stream a Mac camera into the simulator."
        case .restricted: "Camera access is restricted on this Mac."
        default: "Access was denied. Turn on SimCamLite in Privacy & Security › Camera."
        }
    }
}

struct SetupRow: View {
    enum State {
        case done
        case required
        case optional
        case checking
    }

    let symbol: String
    let title: String
    let detail: String
    let state: State
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .animation(.interpolatingSpring(mass: 1, stiffness: 200, damping: 14, initialVelocity: 6), value: state)
    }

    private var tint: Color {
        state == .required ? .orange : .accentColor
    }

    @ViewBuilder
    private var trailing: some View {
        switch state {
        case .done:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.green)
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity), removal: .opacity))
        case .checking:
            ProgressView().controlSize(.small).padding(.horizontal, 12)
        case .required, .optional:
            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            .buttonStyle(.borderedProminent)
            .tint(state == .required ? .orange : .accentColor)
        }
    }
}
