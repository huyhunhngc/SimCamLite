import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// One camera as a compact card, laid out like the Simulator window: title on top, sources beside the preview,
/// adjustments in a bar below.
struct StreamPanel<Accessory: View>: View {
    let title: String
    let symbol: String
    @ObservedObject var stream: StreamController
    let preview: PreviewFeed
    /// Front camera mirroring the back one: shows the preview, controls are inactive.
    var follows = false
    @ViewBuilder var accessory: () -> Accessory
    @State private var importing = false
    @State private var dropTargeted = false
    @State private var cameras: [AVCaptureDevice] = []
    @State private var showingQR = false
    @State private var qrText = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                Spacer()
                accessory()
            }

            HStack(alignment: .center, spacing: 10) {
                PreviewImage(feed: preview)
                    .frame(maxWidth: 300)
                    .overlay {
                        if dropTargeted {
                            RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 3)
                                .overlay(Text("Drop image or video").font(.caption.weight(.semibold)).padding(6)
                                    .background(.regularMaterial, in: Capsule()))
                        }
                    }
                    .overlay(alignment: .topLeading) { if follows { Badge(text: "Same as back") } }
                    .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                        guard !follows, let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in
                            guard let url else { return }
                            Task { @MainActor in stream.useFile(url) }
                        }
                        return true
                    }
                    .help("Drop an image or video here")
                sourceStrip
                    .disabled(follows)
                    .opacity(follows ? 0.4 : 1)
            }

            Text(follows ? "Uses the back camera's source" : stream.source.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            adjustmentBar
                .disabled(follows)
                .opacity(follows ? 0.4 : 1)

            if let error = stream.errorMessage, !follows {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { cameras = MacCameraSource.availableDevices }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie]) { result in
            if case let .success(url) = result {
                stream.useFile(url)
            }
        }
    }

    /// Sources, like the hardware buttons on the side of the Simulator window.
    private var sourceStrip: some View {
        VStack(spacing: 2) {
            BarButton(symbol: SourceKind.testPattern.symbol, help: "Test pattern", active: stream.kind == .testPattern, hintEdge: .leading) {
                stream.useTestPattern()
            }
            BarButton(symbol: "photo.on.rectangle", help: "Image or video… (or drop a file on the preview)",
                      active: stream.kind == .image || stream.kind == .video, hintEdge: .leading) {
                importing = true
            }
            BarButton(symbol: SourceKind.qrCode.symbol, help: "QR code from a link or text", active: stream.kind == .qrCode, hintEdge: .leading) {
                qrText = (stream.source as? QRCodeSource)?.text ?? QRCodeForm.clipboardLink ?? ""
                showingQR = true
            }
            .popover(isPresented: $showingQR, arrowEdge: .trailing) {
                QRCodeForm(text: $qrText) { text in
                    stream.useQRCode(text)
                    if stream.errorMessage == nil { showingQR = false }
                }
            }
            BarMenu(symbol: SourceKind.macCamera.symbol, help: "Mac camera", active: stream.kind == .macCamera, hintEdge: .leading) {
                if cameras.isEmpty { Text("No camera found") }
                ForEach(cameras, id: \.uniqueID) { device in
                    Button(device.localizedName) { stream.useCamera(device) }
                }
            }
            .simultaneousGesture(TapGesture().onEnded { cameras = MacCameraSource.availableDevices })
            let recents = RecentFiles.urls
            BarMenu(symbol: "clock", help: "Recent files", active: false, hintEdge: .leading) {
                if recents.isEmpty { Text("No recent files") }
                ForEach(recents, id: \.self) { url in
                    Button(url.lastPathComponent) { stream.useFile(url) }
                }
            }
        }
        .modifier(GlassBar())
    }

    private var adjustmentBar: some View {
        HStack(spacing: 2) {
            BarButton(symbol: stream.options.fill ? "rectangle.arrowtriangle.2.outward" : "rectangle.arrowtriangle.2.inward",
                      help: stream.options.fill ? "Fill: crops to the sensor · click for Fit" : "Fit: letterboxed · click for Fill",
                      active: stream.options.fill) {
                stream.options.fill.toggle()
            }
            Divider().frame(height: 18)
            BarButton(symbol: "rotate.left", help: "Rotate left 90°") {
                stream.options.rotation = (stream.options.rotation + 3) % 4
            }
            BarButton(symbol: "rotate.right", help: "Rotate right 90° (now \(stream.options.rotation * 90)°)",
                      active: stream.options.rotation != 0) {
                stream.options.rotation = (stream.options.rotation + 1) % 4
            }
            BarButton(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                      help: stream.options.mirror ? "Mirrored · click to unmirror" : "Mirror horizontally",
                      active: stream.options.mirror) {
                stream.options.mirror.toggle()
            }
            if stream.kind == .video {
                Divider().frame(height: 18)
                BarButton(symbol: stream.isPaused ? "play.fill" : "pause.fill", help: stream.isPaused ? "Play" : "Pause") {
                    stream.isPaused.toggle()
                }
            }
        }
        .modifier(GlassBar())
    }
}

extension StreamPanel where Accessory == EmptyView {
    init(title: String, symbol: String, stream: StreamController, preview: PreviewFeed) {
        self.init(title: title, symbol: symbol, stream: stream, preview: preview) { EmptyView() }
    }
}

/// An icon button for the camera card bars; `active` tints it like a selected toolbar item.
struct BarButton: View {
    let symbol: String
    let help: String
    var active = false
    var hintEdge: Edge = .top
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(active ? Color.accentColor : Color.primary)
        .hoverHint(help, edge: hintEdge)
    }
}

struct BarMenu<Content: View>: View {
    let symbol: String
    let help: String
    var active = false
    var hintEdge: Edge = .top
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu(content: content) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(active ? Color.accentColor : Color.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30, height: 30)
        .hoverHint(help, edge: hintEdge)
    }
}

/// A small label shown shortly after the pointer rests on a control. Faster than a native tooltip and visible
/// next to the compact icon bars; still exposed to VoiceOver as the control's label.
private struct HoverHint: ViewModifier {
    let text: String
    let edge: Edge
    @State private var hovering = false
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(text)
            .onHover { inside in
                hovering = inside
                if inside {
                    Task {
                        try? await Task.sleep(for: .milliseconds(400))
                        if hovering { withAnimation(.easeOut(duration: 0.12)) { visible = true } }
                    }
                } else {
                    visible = false
                }
            }
            .overlay(alignment: alignment) {
                // A zero-size anchor on the edge; the hint hangs off it, outside the control.
                Color.clear.frame(width: 0, height: 0)
                    .overlay(alignment: hintAlignment) {
                        if visible {
                            Text(text)
                                .font(.caption)
                                .lineLimit(1)
                                .fixedSize()
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.regularMaterial, in: Capsule())
                                .overlay(Capsule().strokeBorder(.separator))
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
                                .padding(edge == .leading || edge == .trailing ? .horizontal : .vertical, 10)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
            }
            .zIndex(visible ? 1 : 0)
    }

    /// The side of the hint that touches the anchor.
    private var hintAlignment: Alignment {
        switch edge {
        case .leading: .trailing
        case .trailing: .leading
        case .bottom: .top
        case .top: .bottom
        }
    }

    private var alignment: Alignment {
        switch edge {
        case .leading: .leading
        case .trailing: .trailing
        case .bottom: .bottom
        case .top: .top
        }
    }
}

extension View {
    func hoverHint(_ text: String, edge: Edge = .top) -> some View {
        modifier(HoverHint(text: text, edge: edge))
    }
}

/// Liquid Glass capsule on macOS 26, a material capsule before.
struct GlassBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            // Glass as a background, so hover hints can extend past the capsule without being clipped.
            content.padding(4).background { Color.clear.glassEffect(.regular, in: Capsule()) }
        } else {
            content.padding(4).background(.regularMaterial, in: Capsule())
        }
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
