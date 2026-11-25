import Combine
import SwiftUI

/// The selected simulator's live screen beside the camera cards, as wide as the window height allows.
/// Click to tap, drag to swipe, type while it has focus; Home and Lock below.
struct SimulatorPane: View {
    @ObservedObject var screen: SimulatorScreen
    @ObservedObject var simulators: SimulatorModel
    /// Width of the screen the pane sits in.
    let availableWidth: CGFloat

    /// iPhone and iPad screen proportions until the first frame gives the real size.
    static let phoneAspect: CGFloat = 1206.0 / 2622.0
    static let padAspect: CGFloat = 3.0 / 4.0
    /// Widest the screen grows, so the camera cards keep most of the room (an iPad screen is wide).
    static let maxWidth: CGFloat = 420
    static let maxShare: CGFloat = 0.4

    var body: some View {
        let device = simulators.selectedDevice
        VStack(spacing: 10) {
            display(device)
                .frame(maxWidth: min(Self.maxWidth, availableWidth * Self.maxShare), maxHeight: .infinity)
            HStack(spacing: 2) {
                BarButton(symbol: "house", help: "Home") { screen.press(.home) }
                BarButton(symbol: "lock", help: "Lock") { screen.press(.lock) }
            }
            .modifier(GlassBar())
            .disabled(screen.state != .attached)
        }
        .fixedSize(horizontal: true, vertical: false)
        .task(id: device?.isBooted == true ? device?.udid : nil) {
            guard let device, device.isBooted else {
                screen.detach()
                return
            }
            await screen.attach(udid: device.udid)
        }
        .onDisappear { screen.detach() }
    }

    @ViewBuilder
    private func display(_ device: SimulatorDevice?) -> some View {
        let isPad = device.map { RunDestinationPicker.symbol($0) == "ipad" } ?? false
        let aspect = screen.pixelSize.map { $0.width / $0.height } ?? (isPad ? Self.padAspect : Self.phoneAspect)
        ZStack {
            Rectangle().fill(.black)
            switch screen.state {
            case .attached:
                SimulatorDisplay(screen: screen)
            case .attaching:
                ProgressView()
            case let .failed(message):
                status("Can't attach to this simulator", detail: message)
            case .detached:
                if let device, !device.isBooted {
                    VStack(spacing: 10) {
                        status("\(device.name) is shut down", detail: nil)
                        Button {
                            Task { await simulators.boot(device.udid) }
                        } label: {
                            Label("Boot", systemImage: "power")
                        }
                        .disabled(simulators.isBusy)
                    }
                } else if device == nil {
                    status("No simulator", detail: nil)
                }
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func status(_ title: String, detail: String?) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .padding()
    }
}

/// Shows the simulator's IOSurface on a layer and turns mouse and keyboard into simulator input.
private struct SimulatorDisplay: NSViewRepresentable {
    let screen: SimulatorScreen

    func makeNSView(context: Context) -> SimulatorDisplayView {
        let view = SimulatorDisplayView()
        view.screen = screen
        context.coordinator.subscriptions = [
            screen.surface.sink { [weak view] in view?.show($0) },
            screen.frames.sink { [weak view] in view?.refresh() },
        ]
        return view
    }

    func updateNSView(_ view: SimulatorDisplayView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var subscriptions: [AnyCancellable] = []
    }
}

final class SimulatorDisplayView: NSView {
    weak var screen: SimulatorScreen?
    private var surface: IOSurface?
    private var touchEdge: SCLTouchEdge = .none
    /// Points from the screen edge where a drag starts a system edge gesture (swipe up from the bottom goes Home).
    private static let edgeZone: CGFloat = 8

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resize
        focusRingType = .exterior
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func show(_ surface: IOSurface?) {
        self.surface = surface
        layer?.contents = surface
    }

    /// The layer keeps showing its first copy of the surface unless its contents are set again.
    func refresh() {
        guard let surface else { return }
        layer?.contents = nil
        layer?.contents = surface
    }

    // MARK: Focus ring

    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10).fill()
    }
    override func becomeFirstResponder() -> Bool {
        noteFocusRingMaskChanged()
        return true
    }
    override func resignFirstResponder() -> Bool {
        noteFocusRingMaskChanged()
        return true
    }

    // MARK: Touch

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = location(of: event)
        touchEdge = edge(at: point)
        send(.began, point)
    }

    override func mouseDragged(with event: NSEvent) {
        send(.moved, location(of: event))
    }

    override func mouseUp(with event: NSEvent) {
        send(.ended, location(of: event))
        touchEdge = .none
    }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private func edge(at point: CGPoint) -> SCLTouchEdge {
        let zone = Self.edgeZone
        if point.y >= bounds.height - zone { return .bottom }
        if point.y <= zone { return .top }
        if point.x <= zone { return .left }
        if point.x >= bounds.width - zone { return .right }
        return .none
    }

    private func send(_ phase: SCLTouchPhase, _ point: CGPoint) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        screen?.sendTouch(phase, at: CGPoint(x: point.x / bounds.width, y: point.y / bounds.height), edge: touchEdge)
    }

    // MARK: Keyboard

    /// Command shortcuts stay with SimCamLite; everything else is typed into the simulator.
    override func keyDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.command), let usage = HIDKeyboard.usage(for: event.keyCode) else {
            return super.keyDown(with: event)
        }
        screen?.sendKey(usage, down: true)
    }

    override func keyUp(with event: NSEvent) {
        guard let usage = HIDKeyboard.usage(for: event.keyCode) else { return super.keyUp(with: event) }
        screen?.sendKey(usage, down: false)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let (usage, flag) = HIDKeyboard.modifier(for: event.keyCode) else { return super.flagsChanged(with: event) }
        screen?.sendKey(usage, down: event.modifierFlags.rawValue & flag != 0)
    }
}

/// Mac virtual key codes to USB HID keyboard usages (page 0x07), by physical key position.
private enum HIDKeyboard {
    static func usage(for keyCode: UInt16) -> UInt32? { keys[keyCode] }

    /// The HID usage and the left/right device flag (`NX_DEVICE…KEYMASK`) that tells this key's own state.
    static func modifier(for keyCode: UInt16) -> (UInt32, UInt)? { modifiers[keyCode] }

    private static let keys: [UInt16: UInt32] = [
        0x00: 0x04, 0x0B: 0x05, 0x08: 0x06, 0x02: 0x07, 0x0E: 0x08, 0x03: 0x09, 0x05: 0x0A, 0x04: 0x0B,
        0x22: 0x0C, 0x26: 0x0D, 0x28: 0x0E, 0x25: 0x0F, 0x2E: 0x10, 0x2D: 0x11, 0x1F: 0x12, 0x23: 0x13,
        0x0C: 0x14, 0x0F: 0x15, 0x01: 0x16, 0x11: 0x17, 0x20: 0x18, 0x09: 0x19, 0x0D: 0x1A, 0x07: 0x1B,
        0x10: 0x1C, 0x06: 0x1D,
        0x12: 0x1E, 0x13: 0x1F, 0x14: 0x20, 0x15: 0x21, 0x17: 0x22, 0x16: 0x23, 0x1A: 0x24, 0x1C: 0x25,
        0x19: 0x26, 0x1D: 0x27,
        0x24: 0x28, 0x4C: 0x58, 0x35: 0x29, 0x33: 0x2A, 0x30: 0x2B, 0x31: 0x2C, 0x1B: 0x2D, 0x18: 0x2E,
        0x21: 0x2F, 0x1E: 0x30, 0x2A: 0x31, 0x29: 0x33, 0x27: 0x34, 0x32: 0x35, 0x2B: 0x36, 0x2F: 0x37,
        0x2C: 0x38, 0x75: 0x4C, 0x73: 0x4A, 0x77: 0x4D, 0x74: 0x4B, 0x79: 0x4E,
        0x7C: 0x4F, 0x7B: 0x50, 0x7D: 0x51, 0x7E: 0x52,
    ]

    private static let modifiers: [UInt16: (UInt32, UInt)] = [
        0x3B: (0xE0, 0x0001), 0x38: (0xE1, 0x0002), 0x3A: (0xE2, 0x0020),
        0x3E: (0xE4, 0x2000), 0x3C: (0xE5, 0x0004), 0x3D: (0xE6, 0x0040),
    ]
}
