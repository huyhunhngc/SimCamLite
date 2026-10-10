import AppKit
import AVFoundation
import Combine
import UniformTypeIdentifiers

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []
    private let onOpenMain: () -> Void
    private let onOpenPermissions: () -> Void

    init(model: AppModel, onOpenMain: @escaping () -> Void, onOpenPermissions: @escaping () -> Void) {
        self.model = model
        self.onOpenMain = onOpenMain
        self.onOpenPermissions = onOpenPermissions
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.toolTip = "SimCamLite"
        updateIcon(connected: false)
        model.$clients
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] connected in self?.updateIcon(connected: connected) }
            .store(in: &cancellables)
    }

    private func updateIcon(connected: Bool) {
        let name = connected ? "camera.fill" : "camera"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "SimCamLite")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.permissions.refresh()
        Task { await model.simulators.refresh() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        CLIInstaller.shared.refresh()
        menu.addItem(.sectionHeader(title: "SimCamLite Camera Control"))
        menu.addItem(item(model.isStreaming ? "Stop Streaming" : "Start Streaming",
                          symbol: model.isStreaming ? "stop.fill" : "play.fill") { [model] in
            model.isStreaming ? model.stopStreaming() : model.startStreaming()
        })
        menu.addItem(.separator())

        if model.frontSeparate {
            addSourceSection(title: "Back camera", stream: model.back, to: menu)
            menu.addItem(.separator())
            addSourceSection(title: "Front camera", stream: model.front, to: menu)
        } else {
            addSourceSection(title: "Camera source", stream: model.back, to: menu)
        }
        menu.addItem(.separator())

        menu.addItem(item("Control front/back separately", state: model.frontSeparate) { [model] in
            model.frontSeparate.toggle()
        })
        menu.addItem(submenuItem("Device profile", submenu: deviceProfileMenu()))
        menu.addItem(submenuItem("Frame rate", submenu: frameRateMenu()))
        menu.addItem(.separator())

        addSimulatorSection(to: menu)
        addClientSection(to: menu)
        menu.addItem(.separator())

        menu.addItem(item("Open SimCamLite…", key: ",") { [onOpenMain] in onOpenMain() })
        menu.addItem(item(permissionsTitle) { [onOpenPermissions] in onOpenPermissions() })
        menu.addItem(item(CLIInstaller.shared.menuTitle, symbol: "terminal") { CLIInstaller.shared.installInteractively() })
        menu.addItem(.separator())
        menu.addItem(item("Quit SimCamLite", key: "q") { NSApp.terminate(nil) })
    }

    private var permissionsTitle: String {
        let needsAttention = model.permissions.cameraBlocked || !model.injectInstalled || model.simulators.toolsAvailable == false
            || CLIInstaller.shared.isStale
        return needsAttention ? "Permissions & Setup… ⚠︎" : "Permissions & Setup…"
    }

    private func addSourceSection(title: String, stream: StreamController, to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: title))
        menu.addItem(item(SourceKind.testPattern.title, symbol: SourceKind.testPattern.symbol, state: stream.kind == .testPattern) {
            stream.useTestPattern()
        })

        let cameraItem = submenuItem(SourceKind.macCamera.title, symbol: SourceKind.macCamera.symbol, submenu: cameraMenu(for: stream))
        cameraItem.state = stream.kind == .macCamera ? .on : .off
        if let id = stream.cameraDeviceID, let name = AVCaptureDevice(uniqueID: id)?.localizedName {
            cameraItem.attributedTitle = titleWithDetail(SourceKind.macCamera.title, detail: name)
        }
        menu.addItem(cameraItem)

        let fileItem = submenuItem("Image / Video", symbol: SourceKind.image.symbol, submenu: fileMenu(for: stream))
        fileItem.state = stream.kind == .image || stream.kind == .video ? .on : .off
        if let url = stream.fileURL {
            fileItem.attributedTitle = titleWithDetail("Image / Video", detail: url.lastPathComponent)
        }
        menu.addItem(fileItem)

        menu.addItem(submenuItem("Adjust", symbol: "slider.horizontal.3", submenu: adjustMenu(for: stream)))

        if stream.kind == .video {
            menu.addItem(item(stream.isPaused ? "Play video" : "Pause video", symbol: stream.isPaused ? "play.fill" : "pause.fill") {
                stream.isPaused.toggle()
            })
        }
    }

    private func cameraMenu(for stream: StreamController) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        if model.permissions.cameraBlocked {
            menu.addItem(item("Allow Camera Access…", symbol: "exclamationmark.triangle") { [onOpenPermissions] in onOpenPermissions() })
            return menu
        }
        let devices = MacCameraSource.availableDevices
        if devices.isEmpty {
            menu.addItem(disabledItem("No camera found"))
        }
        for device in devices {
            menu.addItem(item(device.localizedName, state: stream.cameraDeviceID == device.uniqueID) {
                stream.useCamera(device)
            })
        }
        return menu
    }

    private func fileMenu(for stream: StreamController) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Choose File…", symbol: "folder") { [weak self] in self?.chooseFile(for: stream) })
        let recents = RecentFiles.urls
        if !recents.isEmpty {
            menu.addItem(.separator())
            menu.addItem(.sectionHeader(title: "Recent"))
            for url in recents {
                let isVideo = UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false
                menu.addItem(item(url.lastPathComponent, symbol: isVideo ? SourceKind.video.symbol : SourceKind.image.symbol,
                                  state: stream.fileURL == url) {
                    stream.useFile(url)
                })
            }
            menu.addItem(.separator())
            menu.addItem(item("Clear Recent") { RecentFiles.clear() })
        }
        return menu
    }

    private func adjustMenu(for stream: StreamController) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(item("Fill", state: stream.options.fill) { stream.options.fill = true })
        menu.addItem(item("Fit", state: !stream.options.fill) { stream.options.fill = false })
        menu.addItem(.separator())
        menu.addItem(item("Rotate 90°", symbol: "rotate.right") { stream.options.rotation = (stream.options.rotation + 1) % 4 })
        menu.addItem(item("Mirror", state: stream.options.mirror) { stream.options.mirror.toggle() })
        return menu
    }

    private func deviceProfileMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for profile in DeviceProfile.allCases {
            menu.addItem(item(profile.title, state: model.deviceProfile == profile) { [model] in model.deviceProfile = profile })
        }
        menu.addItem(.separator())
        menu.addItem(disabledItem("Applies to apps launched afterwards"))
        return menu
    }

    private func frameRateMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for rate in FrameRate.allCases {
            menu.addItem(item(rate.title, state: model.frameRate == rate) { [model] in model.frameRate = rate })
        }
        return menu
    }

    private func addSimulatorSection(to menu: NSMenu) {
        let simulators = model.simulators
        menu.addItem(.sectionHeader(title: "Simulators"))
        if simulators.toolsAvailable == false {
            menu.addItem(disabledItem("Xcode simulator tools unavailable"))
            return
        }
        let injectAll = item("Inject into Every Simulator", state: simulators.injectsAllSimulators) {
            Task { await simulators.setInjectsAllSimulators(!simulators.injectsAllSimulators) }
        }
        injectAll.toolTip = "Enable injection on every simulator as it boots"
        injectAll.isEnabled = model.injectInstalled
        if simulators.devices.isEmpty {
            menu.addItem(disabledItem("No booted simulator"))
            menu.addItem(item("Open Simulator", symbol: "iphone") { simulators.openSimulatorApp() })
            menu.addItem(injectAll)
            return
        }
        for device in simulators.devices {
            let enabled = simulators.isInjectionEnabled(device.udid)
            let deviceItem = submenuItem("\(device.name) (\(device.runtime))", submenu: simulatorMenu(for: device))
            deviceItem.image = Self.dot(enabled ? .systemGreen : .systemOrange)
            deviceItem.toolTip = enabled ? "SimCamLite is injected into apps launched on this simulator" : "Injection is off for this simulator"
            menu.addItem(deviceItem)
        }
        menu.addItem(injectAll)
    }

    private func simulatorMenu(for device: SimulatorDevice) -> NSMenu {
        let simulators = model.simulators
        let injectAvailable = model.injectInstalled
        let menu = NSMenu()
        menu.autoenablesItems = false
        let enabled = simulators.isInjectionEnabled(device.udid)
        let toggle = item("Inject into All Apps", state: enabled) {
            Task { await simulators.setInjection(!enabled, udid: device.udid) }
        }
        toggle.isEnabled = injectAvailable
        menu.addItem(toggle)
        menu.addItem(disabledItem(simulators.isInjectionRemembered(device.udid)
            ? "Restored after the simulator restarts" : "Apps opened after enabling use SimCamLite"))
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Launch with SimCamLite"))
        let apps = simulators.apps(for: device.udid)
        if apps.isEmpty {
            menu.addItem(disabledItem("No user apps installed"))
        }
        for app in apps {
            let launch = item(app.name) { Task { await simulators.launch(app, udid: device.udid) } }
            launch.toolTip = app.bundleID
            launch.isEnabled = injectAvailable
            menu.addItem(launch)
        }
        menu.addItem(.separator())
        menu.addItem(item("Copy Xcode Environment Variable", symbol: "doc.on.doc") { simulators.copyXcodeEnvironment() })
        return menu
    }

    private func addClientSection(to menu: NSMenu) {
        guard !model.clients.isEmpty else { return }
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Connected apps"))
        for client in model.clients {
            let entry = disabledItem("")
            entry.attributedTitle = titleWithDetail(client.processName, detail: "\(client.cameraDescription) · \(client.photoCount) photos")
            entry.image = Self.dot(client.cameraState == UInt32(SCLClientCameraIdle) ? .systemGray : .systemGreen)
            menu.addItem(entry)
        }
    }

    private func chooseFile(for stream: StreamController) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.message = "Choose an image or video to use as the camera source"
        if panel.runModal() == .OK, let url = panel.url {
            stream.useFile(url)
        }
    }

    private func item(_ title: String, symbol: String? = nil, key: String = "", state: Bool? = nil, action: @escaping () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title: title, keyEquivalent: key, handler: action)
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        if let state {
            item.state = state ? .on : .off
        }
        return item
    }

    private func submenuItem(_ title: String, symbol: String? = nil, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        item.submenu = submenu
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func titleWithDetail(_ title: String, detail: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: title, attributes: [.font: NSFont.menuFont(ofSize: 0)])
        result.append(NSAttributedString(string: "  \(detail)", attributes: [
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return result
    }

    private static func dot(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 10, height: 10), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}

final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(runHandler), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runHandler() {
        handler()
    }
}
