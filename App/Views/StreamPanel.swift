import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// One camera's preview and settings, laid out as a grouped-form row (System Settings style).
struct StreamPanel: View {
    @ObservedObject var stream: StreamController
    let preview: PreviewFeed
    @State private var importing = false
    @State private var dropTargeted = false
    @State private var cameras: [AVCaptureDevice] = []
    @State private var showingQR = false
    @State private var qrText = ""

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            PreviewImage(feed: preview)
                .frame(width: 200)
                .overlay {
                    if dropTargeted {
                        RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 3)
                            .overlay(Text("Drop image or video").font(.caption.weight(.semibold)).padding(6)
                                .background(.regularMaterial, in: Capsule()))
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in stream.useFile(url) }
                    }
                    return true
                }
                .help("Drop an image or video here")

            VStack(spacing: 0) {
                SettingRow("Source") { sourceMenu }
                Divider()
                SettingRow("Scaling") {
                    Picker("Scaling", selection: $stream.options.fill) {
                        Text("Fill").tag(true)
                        Text("Fit").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Divider()
                SettingRow("Rotation") {
                    HStack(spacing: 8) {
                        Text("\(stream.options.rotation * 90)°").monospacedDigit().foregroundStyle(.secondary)
                        Button { stream.options.rotation = (stream.options.rotation + 3) % 4 } label: { Image(systemName: "rotate.left") }
                            .help("Rotate left 90°")
                        Button { stream.options.rotation = (stream.options.rotation + 1) % 4 } label: { Image(systemName: "rotate.right") }
                            .help("Rotate right 90°")
                    }
                }
                Divider()
                SettingRow("Mirror") {
                    Toggle("Mirror", isOn: $stream.options.mirror).toggleStyle(.switch).labelsHidden().controlSize(.small)
                }
                if stream.kind == .video {
                    Divider()
                    SettingRow("Playback") {
                        Button { stream.isPaused.toggle() } label: {
                            Label(stream.isPaused ? "Play" : "Pause", systemImage: stream.isPaused ? "play.fill" : "pause.fill")
                        }
                    }
                }
                if let error = stream.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { cameras = MacCameraSource.availableDevices }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie]) { result in
            if case let .success(url) = result {
                stream.useFile(url)
            }
        }
    }

    private var sourceMenu: some View {
        Menu {
            Button { stream.useTestPattern() } label: { Label("Test Pattern", systemImage: SourceKind.testPattern.symbol) }
            Button { showQRForm() } label: { Label("QR Code…", systemImage: SourceKind.qrCode.symbol) }
            Divider()
            Button { importing = true } label: { Label("Image or Video…", systemImage: "folder") }
            let recents = RecentFiles.urls
            if !recents.isEmpty {
                Menu {
                    ForEach(recents, id: \.self) { url in
                        Button(url.lastPathComponent) { stream.useFile(url) }
                    }
                } label: {
                    Label("Recent Files", systemImage: "clock")
                }
            }
            Divider()
            Section("Mac Cameras") {
                if cameras.isEmpty { Text("No camera found") }
                ForEach(cameras, id: \.uniqueID) { device in
                    Button { stream.useCamera(device) } label: { Label(device.localizedName, systemImage: SourceKind.macCamera.symbol) }
                }
            }
        } label: {
            Label(stream.source.title, systemImage: stream.kind.symbol)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: 240)
        .simultaneousGesture(TapGesture().onEnded { cameras = MacCameraSource.availableDevices })
        .popover(isPresented: $showingQR, arrowEdge: .bottom) {
            QRCodeForm(text: $qrText) { text in
                stream.useQRCode(text)
                if stream.errorMessage == nil { showingQR = false }
            }
        }
    }

    private func showQRForm() {
        qrText = (stream.source as? QRCodeSource)?.text ?? QRCodeForm.clipboardLink ?? ""
        showingQR = true
    }
}

/// A label on the left and its control on the right, like a Form row inside a custom layout.
private struct SettingRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            content()
        }
        .frame(minHeight: 32)
    }
}

/// Popover for the QR source: type or paste a link, or pick a recent one.
struct QRCodeForm: View {
    @Binding var text: String
    let onApply: (String) -> Void
    private let recents = RecentQRCodes.texts

    static var clipboardLink: String? {
        guard let value = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value), url.scheme != nil else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("QR code", systemImage: SourceKind.qrCode.symbol).font(.headline)
            Text("The camera shows this link or text as a QR code.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("https://example.com", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit { onApply(text) }
            if !recents.isEmpty {
                Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(recents, id: \.self) { recent in
                    Button { onApply(recent) } label: {
                        Text(recent).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                Button("Paste") {
                    if let value = NSPasteboard.general.string(forType: .string) { text = value }
                }
                Spacer()
                Button("Show QR Code") { onApply(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
