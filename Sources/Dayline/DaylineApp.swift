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
    private var store: TodayStore?
    private var panelController: FloatingPanelController?
    private var automationController: AutomationController?
    private var pendingAutomationURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationMenu()

        let store = TodayStore()
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
        NSApplication.shared.mainMenu = mainMenu
    }
}
