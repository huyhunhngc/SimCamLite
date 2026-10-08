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
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusMenu: StatusMenuController?
    private var mainWindow: NSWindow?
    private var permissionsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onShowPermissions = { [weak self] in self?.showPermissions() }
        model.start()
        statusMenu = StatusMenuController(
            model: model,
            onOpenMain: { [weak self] in self?.showMainWindow() },
            onOpenPermissions: { [weak self] in self?.showPermissions() }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
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
                .frame(minWidth: 980, minHeight: 680)
            mainWindow = makeWindow(title: "SimCamLite", autosave: "MainWindow", content: root,
                                    style: [.titled, .closable, .miniaturizable, .resizable])
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

    private func makeWindow<Content: View>(title: String, autosave: String, content: Content, style: NSWindow.StyleMask) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
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
