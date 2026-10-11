import SwiftUI

@main
struct SimCamLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Open SimCamLite…") { delegate.showMainWindow() }
                    .keyboardShortcut(",")
                Button("Permissions & Setup…") { delegate.showPermissions() }
                Button("Install Command Line Tool…") { CLIInstaller.shared.installInteractively() }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusMenu: StatusMenuController?
    private var controlServer: ControlServer?
    private var mainWindow: NSWindow?
    private var permissionsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onShowPermissions = { [weak self] in self?.showPermissions() }
        model.start()
        let handler = ControlHandler(model: model)
        let server = ControlServer { await handler.handle($0) }
        do {
            try server.start()
            controlServer = server
        } catch {
            NSLog("SimCamLite: CLI control unavailable: \(error.localizedDescription)")
        }
        statusMenu = StatusMenuController(
            model: model,
            onOpenMain: { [weak self] in self?.showMainWindow() },
            onOpenPermissions: { [weak self] in self?.showPermissions() }
        )
        // `simcam` starts the app with --background; opened by the user it shows the window.
        if !ProcessInfo.processInfo.arguments.contains("--background") {
            showMainWindow()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controlServer?.stop()
        model.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func showMainWindow() {
        if mainWindow == nil {
            let root = ContentView(model: model)
                .frame(minWidth: 900, minHeight: 640)
            let window = makeWindow(title: "SimCamLite", autosave: "MainWindow", content: root,
                                    style: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                    bridgesToolbar: true)
            window.toolbarStyle = .unified
            // The toolbar's run destination takes the title's place, as in Xcode; the title still names the window in menus.
            window.titleVisibility = .hidden
            window.minSize = NSSize(width: 900, height: 640)
            mainWindow = window
        }
        present(mainWindow)
    }

    func showPermissions() {
        if permissionsWindow == nil {
            let root = PermissionsView(model: model, permissions: model.permissions, simulators: model.simulators) { [weak self] in
                self?.permissionsWindow?.close()
            }
            permissionsWindow = makeWindow(title: "Permissions & Setup", autosave: "PermissionsWindow", content: root,
                                           style: [.titled, .closable])
        }
        present(permissionsWindow)
    }

    private func makeWindow<Content: View>(title: String, autosave: String, content: Content, style: NSWindow.StyleMask,
                                         bridgesToolbar: Bool = false) -> NSWindow {
        let host = NSHostingController(rootView: content)
        // Lets SwiftUI `.toolbar` drive this AppKit window.
        if bridgesToolbar {
            host.sceneBridgingOptions = [.toolbars]
            // The window keeps its own (autosaved) size; content min sizes must not grow or clip it.
            host.sizingOptions = []
        }
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = style
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(autosave)
        if !window.setFrameUsingName(autosave) {
            window.center()
        }
        return window
    }

    private func present(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
