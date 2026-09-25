import Cocoa

final class SettingsWindowController: NSWindowController {

    // MARK: - UI

    private var apiKeyField: NSSecureTextField!
    private var validateButton: NSButton!
    private var statusLabel: NSTextField!
    private var statusIcon: NSTextField!
    private var modelLabel: NSTextField!
    private var modelPopup: NSPopUpButton!
    private var removeButton: NSButton!
    private var spinner: NSProgressIndicator!

    // MARK: - Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Fluent — Settings"
        window.center()
        self.init(window: window)
        buildUI()
        loadCurrentState()
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // Section header
        let header = makeLabel("Anthropic API Key", size: 13, bold: true)

        // API key input
        apiKeyField = NSSecureTextField(frame: .zero)
        apiKeyField.placeholderString = "sk-ant-…"
        apiKeyField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        apiKeyField.target = self
        apiKeyField.action = #selector(validateAndSave)

        // Status row
        statusIcon = makeLabel("", size: 13, bold: false)
        statusLabel = makeLabel("Not connected", size: 12, bold: false)
        statusLabel.textColor = .secondaryLabelColor

        let statusRow = NSStackView(views: [statusIcon, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.spacing = 4
        statusRow.alignment = .centerY

        // Spinner
        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isHidden = true

        // Buttons row
        validateButton = NSButton(title: "Validate & Save", target: self, action: #selector(validateAndSave))
        validateButton.bezelStyle = .rounded
        validateButton.keyEquivalent = "\r"

        removeButton = NSButton(title: "Remove Key", target: self, action: #selector(removeKey))
        removeButton.bezelStyle = .rounded
        removeButton.isHidden = true

        let buttonRow = NSStackView(views: [spinner, removeButton, NSView(), validateButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        let spacer = buttonRow.views[2]
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Model picker
        modelLabel = makeLabel("Model", size: 13, bold: true)
        modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modelPopup.addItem(withTitle: "— validate key to load models —")
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)

        // Divider
        let divider = NSBox()
        divider.boxType = .separator

        // Footer note
        let footer = makeLabel(
            "Your key is stored securely in the macOS Keychain and never leaves your device.",
            size: 10, bold: false
        )
        footer.textColor = .tertiaryLabelColor
        footer.maximumNumberOfLines = 2
        footer.lineBreakMode = .byWordWrapping

        // Layout
        let stack = NSStackView(views: [
            header,
            apiKeyField,
            statusRow,
            buttonRow,
            divider,
            modelLabel,
            modelPopup,
            NSView(),
            footer,
        ])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .left
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            apiKeyField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelPopup.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    // MARK: - Load state

    private func loadCurrentState() {
        if let existing = KeychainStore.load(account: "anthropic"), !existing.isEmpty {
            // Show masked key
            apiKeyField.stringValue = existing
            setStatus(connected: true)
            removeButton.isHidden = false
            fetchModels(key: existing)
        } else {
            setStatus(connected: false)
        }
    }

    // MARK: - Actions

    @objc private func validateAndSave() {
        let key = apiKeyField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            setStatus(message: "Please enter an API key.", color: .systemOrange)
            return
        }

        setLoading(true)
        AnthropicClient.shared.validateAndFetchModels(key: key) { [weak self] result in
            DispatchQueue.main.async {
                self?.setLoading(false)
                switch result {
                case .success(let models):
                    do {
                        try KeychainStore.save(key: key, account: "anthropic")
                        self?.setStatus(connected: true)
                        self?.removeButton.isHidden = false
                        self?.populateModels(models)
                    } catch {
                        self?.setStatus(message: "Keychain error: \(error.localizedDescription)", color: .systemRed)
                    }
                case .failure(let error):
                    self?.setStatus(message: error.localizedDescription, color: .systemRed)
                    self?.removeButton.isHidden = true
                }
            }
        }
    }

    @objc private func removeKey() {
        KeychainStore.delete(account: "anthropic")
        apiKeyField.stringValue = ""
        modelPopup.removeAllItems()
        modelPopup.addItem(withTitle: "— validate key to load models —")
        setStatus(connected: false)
        removeButton.isHidden = true
    }

    @objc private func modelChanged() {
        guard let selected = modelPopup.selectedItem?.representedObject as? String else { return }
        UserDefaults.standard.set(selected, forKey: "anthropicModel")
    }

    // MARK: - Helpers

    private func fetchModels(key: String) {
        AnthropicClient.shared.validateAndFetchModels(key: key) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let models) = result {
                    self?.populateModels(models)
                }
            }
        }
    }

    private func populateModels(_ models: [ModelInfo]) {
        let saved = UserDefaults.standard.string(forKey: "anthropicModel")
        modelPopup.removeAllItems()
        for m in models {
            let item = NSMenuItem(title: m.displayName, action: nil, keyEquivalent: "")
            item.representedObject = m.id
            modelPopup.menu?.addItem(item)
        }
        // Select previously saved model, or default to first
        if let saved, let idx = models.firstIndex(where: { $0.id == saved }) {
            modelPopup.selectItem(at: idx)
        } else if !models.isEmpty {
            modelPopup.selectItem(at: 0)
            UserDefaults.standard.set(models[0].id, forKey: "anthropicModel")
        }
    }

    private func setStatus(connected: Bool) {
        if connected {
            statusIcon.stringValue = "✅"
            statusLabel.stringValue = "Connected"
            statusLabel.textColor = .systemGreen
        } else {
            statusIcon.stringValue = "○"
            statusLabel.stringValue = "Not connected"
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    private func setStatus(message: String, color: NSColor) {
        statusIcon.stringValue = "⚠️"
        statusLabel.stringValue = message
        statusLabel.textColor = color
    }

    private func setLoading(_ loading: Bool) {
        validateButton.isEnabled = !loading
        if loading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        spinner.isHidden = !loading
    }

    private func makeLabel(_ text: String, size: CGFloat, bold: Bool) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        return label
    }
}
