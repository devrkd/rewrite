import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController!
    private var textMonitor: TextMonitor!
    private var settingsWindowController: SettingsWindowController?
    private var activeSuggestion: SuggestionWindowController?

    // Retained AX element so TextInjector can inject even if focus shifted to the panel
    private var pendingElement: AXUIElement?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermissionIfNeeded()

        menuBarController = MenuBarController()
        menuBarController.onOpenSettings = { [weak self] in self?.openSettings() }

        textMonitor = TextMonitor()
        textMonitor.onTrigger = { [weak self] text, mode, element, frame in
            DispatchQueue.main.async {
                self?.handleTrigger(text: text, mode: mode, element: element, frame: frame)
            }
        }
        textMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        textMonitor.stop()
    }

    // MARK: - Settings

    func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Trigger handling

    private func handleTrigger(text: String, mode: String, element: AXUIElement, frame: CGRect) {
        // Dismiss any previous suggestion panel first
        activeSuggestion?.close()
        activeSuggestion = nil

        pendingElement = element
        menuBarController.showLoadingIndicator()

        // Show loading panel near the element immediately
        let suggestion = SuggestionWindowController.show(
            anchor: frame,
            phase: .loading(mode: mode)
        )

        // SINGLE guaranteed reset point: fires exactly once no matter how the
        // popup closes (accept, reject, settings, escape). This is the only
        // place `pendingElement`/`activeSuggestion` get cleared and the only
        // place the monitor is told it's safe to detect the next trigger —
        // so there is no path that can leave the app permanently "stuck".
        suggestion.onDismissed = { [weak self] in
            self?.pendingElement = nil
            self?.activeSuggestion = nil
            self?.menuBarController.hideLoadingIndicator()
            self?.textMonitor.reset()
        }
        activeSuggestion = suggestion

        AnthropicClient.shared.correct(text: text, mode: mode) { [weak self, weak suggestion] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.menuBarController.hideLoadingIndicator()

                switch result {
                case .success(let response):
                    suggestion?.update(phase: .result(
                        response: response,
                        onAccept: { [weak self] in
                            guard let element = self?.pendingElement else { return }
                            TextInjector.inject(text: response.corrected, into: element)
                        },
                        onReject: { [weak self] in
                            guard let element = self?.pendingElement else { return }
                            TextInjector.inject(text: response.original, into: element)
                        }
                    ))

                case .failure(let error):
                    let anthError = error as? AnthropicError
                    suggestion?.update(phase: .error(
                        message: error.localizedDescription,
                        isAuth: anthError?.isAuthError ?? false,
                        onOpenSettings: { [weak self] in self?.openSettings() }
                    ))
                }
            }
        }
    }

    // MARK: - Accessibility permission

    private func requestAccessibilityPermissionIfNeeded() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            NSLog("[Fluent] Accessibility not yet granted — prompting user.")
        }
    }
}
