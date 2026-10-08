import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct StreamPanel: View {
    let title: String
    @ObservedObject var stream: StreamController
    let preview: CGImage?
    @State private var importing = false
    @State private var dropTargeted = false
    @State private var cameras: [AVCaptureDevice] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            PreviewImage(image: preview)
                .overlay {
                    if dropTargeted {
                        RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topLeading) { Badge(text: stream.source.title) }
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in stream.useFile(url) }
                    }
                    return true
                }

            HStack(spacing: 6) {
                Button { stream.useTestPattern() } label: { Label("Pattern", systemImage: SourceKind.testPattern.symbol) }
                Button { importing = true } label: { Label("File…", systemImage: "folder") }
                Menu {
                    if cameras.isEmpty {
                        Text("No camera found")
                    }
                    ForEach(cameras, id: \.uniqueID) { device in
                        Button(device.localizedName) { stream.useCamera(device) }
                    }
                } label: {
                    Label("Mac camera", systemImage: SourceKind.macCamera.symbol)
                }
                .onAppear { cameras = MacCameraSource.availableDevices }
                .simultaneousGesture(TapGesture().onEnded { cameras = MacCameraSource.availableDevices })
            }
            .controlSize(.small)

            HStack(spacing: 12) {
                Picker("", selection: $stream.options.fill) {
                    Text("Fill").tag(true)
                    Text("Fit").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 110)
                Button { stream.options.rotation = (stream.options.rotation + 1) % 4 } label: {
                    Image(systemName: "rotate.right")
                }
                .help("Rotate source 90°")
                Toggle("Mirror", isOn: $stream.options.mirror)
                if stream.kind == .video {
                    Button { stream.isPaused.toggle() } label: {
                        Image(systemName: stream.isPaused ? "play.fill" : "pause.fill")
                    }
                }
            }
            .controlSize(.small)

            if let error = stream.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie]) { result in
            if case let .success(url) = result {
                stream.useFile(url)
            }
        }
    }
}
