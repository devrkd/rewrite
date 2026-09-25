import AppKit

final class MenuBarController {

    private var statusItem: NSStatusItem!
    private var loadingItem: NSMenuItem!

    /// Called when the user chooses Settings from the menu.
    var onOpenSettings: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setButtonIcon(symbolName: "pencil.and.sparkles", fallbackText: "✦")
        buildMenu()
    }

    private func setButtonIcon(symbolName: String, fallbackText: String) {
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Fluent") {
            button.image = image
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            button.image = nil
            button.title = fallbackText
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        loadingItem = NSMenuItem(title: "Idle", action: nil, keyEquivalent: "")
        loadingItem.isEnabled = false
        menu.addItem(loadingItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About Fluent", action: #selector(openAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - State indicators

    func showLoadingIndicator() {
        DispatchQueue.main.async { [weak self] in
            self?.setButtonIcon(symbolName: "ellipsis", fallbackText: "…")
            self?.loadingItem.title = "Processing…"
        }
    }

    func hideLoadingIndicator() {
        DispatchQueue.main.async { [weak self] in
            self?.setButtonIcon(symbolName: "pencil.and.sparkles", fallbackText: "✦")
            self?.loadingItem.title = "Idle"
        }
    }

    // MARK: - Actions

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func openAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }
}
