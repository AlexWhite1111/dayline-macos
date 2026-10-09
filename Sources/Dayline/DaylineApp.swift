import AppKit
import DaylineAutomation

@main
struct DaylineApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: TimelineStore?
    private var panelController: FloatingPanelController?
    private var automationController: AutomationController?
    private var pendingAutomationURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationMenu()

        let store = TimelineStore()
        let controller = FloatingPanelController(store: store)
        self.store = store
        self.panelController = controller
        automationController = AutomationController(store: store)
        controller.show()

        pendingAutomationURLs.forEach(handleAutomationURL)
        pendingAutomationURLs.removeAll()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard automationController != nil else {
            pendingAutomationURLs.append(contentsOf: urls)
            return
        }
        urls.forEach(handleAutomationURL)
    }

    func applicationDidResignActive(_ notification: Notification) {
        store?.commitEditing()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store?.commitEditing()
        store?.persist()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func handleAutomationURL(_ url: URL) {
        do {
            let request = try DaylineAutomationRequest(url: url)
            guard let automationController else { return }
            let response = automationController.execute(request)
            try DaylineAutomationResponses.write(response, for: request.requestID)
        } catch {
            NSLog("Dayline automation failed: \(error.localizedDescription)")
        }
    }

    private func installApplicationMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "今日")
        appMenu.addItem(
            withTitle: "退出今日",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApplication.shared.mainMenu = mainMenu
    }
}
