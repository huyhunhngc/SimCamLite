import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    StreamPanel(title: "Back camera", stream: model.back, preview: model.backPreview)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Front camera uses back source", isOn: $model.frontFollowsBack)
                        if model.frontFollowsBack {
                            PreviewImage(feed: model.frontPreview)
                                .overlay(alignment: .topLeading) { Badge(text: "Front") }
                            Spacer(minLength: 0)
                        } else {
                            StreamPanel(title: "Front camera", stream: model.front, preview: model.frontPreview)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(16)
                Divider()
                StatusBar(model: model)
            }
            .frame(minWidth: 640)
            SimulatorPanel(model: model, simulators: model.simulators)
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.toast)
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

struct StatusBar: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            Button {
                model.isStreaming ? model.stopStreaming() : model.startStreaming()
            } label: {
                Image(systemName: model.isStreaming ? "stop.fill" : "play.fill")
            }
            .help(model.isStreaming ? "Stop streaming" : "Start streaming")
            Group {
                if !model.sharedMemoryReady {
                    Label("Shared memory unavailable", systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                } else if model.isStreaming {
                    Label("Streaming \(model.frameRate.title)", systemImage: "dot.radiowaves.left.and.right").foregroundStyle(.green)
                } else {
                    Label("Stopped", systemImage: "pause.circle").foregroundStyle(.secondary)
                }
            }
            Label(model.injectInstalled ? "Inject library installed" : "Inject library missing",
                  systemImage: model.injectInstalled ? "checkmark.seal" : "xmark.seal")
                .foregroundStyle(model.injectInstalled ? Color.secondary : Color.red)
                .help(model.installError ?? InjectInstaller.loaderPath)
            Spacer()
            Picker("Frame rate", selection: $model.frameRate) {
                ForEach(FrameRate.allCases) { Text($0.title).tag($0) }
            }
            .frame(maxWidth: 160)
            .help("Maximum rate sent to the simulator. Apps receive up to their activeVideoMinFrameDuration.")
            Picker("Device profile", selection: $model.deviceProfile) {
                ForEach(DeviceProfile.allCases) { Text($0.title).tag($0) }
            }
            .frame(maxWidth: 280)
            .help("Applies to apps launched after the change")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
