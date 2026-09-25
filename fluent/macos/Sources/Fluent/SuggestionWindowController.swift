import Cocoa

/// Compact, borderless popover that appears near the cursor — Grammarly-style.
final class SuggestionWindowController: NSObject, NSWindowDelegate {

    // MARK: - Phase

    enum Phase {
        case loading(mode: String)
        case result(response: CorrectResponse, onAccept: () -> Void, onReject: () -> Void)
        case error(message: String, isAuth: Bool, onOpenSettings: () -> Void)
    }

    // MARK: - Properties

    private var panel: NSPanel!
    /// The popup's width is dynamic — computed from the shown text and clamped to
    /// this range — so a short fix stays compact and a long rewrite gets more
    /// room instead of wrapping into a tall, narrow column.
    private let minWidth: CGFloat = 280
    private let maxWidth: CGFloat = 560
    private var currentWidth: CGFloat = 300
    private var rootWidthConstraint: NSLayoutConstraint!
    private var correctedScrollWidthConstraint: NSLayoutConstraint!
    /// Anchor last passed to `position(near:)`, kept so the popup can be
    /// re-centered on it whenever a phase change resizes the panel.
    private var lastAnchor: CGRect?
    /// Above this height, the corrected-text area scrolls instead of growing further —
    /// raised generously so most rewrites fit without scrolling; the user can still
    /// drag the panel bigger (or smaller) since the window is resizable.
    private let maxCorrectedTextHeight: CGFloat = 420

    // Loading
    private var loadingView: NSView!
    private var spinner: NSProgressIndicator!
    private var loadingLabel: NSTextField!
    private var loadingDismissButton: NSButton!

    // Result
    private var resultView: NSView!
    private var modeLabel: NSTextField!
    private var correctedLabel: NSTextField!
    private var correctedScrollView: NSScrollView!
    private var correctedLabelHeightConstraint: NSLayoutConstraint!
    private var correctedScrollHeightConstraint: NSLayoutConstraint!
    private var acceptButton: NSButton!
    private var rejectButton: NSButton!

    // Error
    private var errorView: NSView!
    private var errorMsgLabel: NSTextField!
    private var settingsButton: NSButton!
    private var errorDismissButton: NSButton!

    private var acceptHandler: (() -> Void)?
    private var rejectHandler: (() -> Void)?
    private var settingsHandler: (() -> Void)?
    /// Called EXACTLY ONCE, from every single dismissal path (accept, reject,
    /// settings, escape, or system close) — the one guaranteed place to reset
    /// any external state tied to "a popup is currently showing".
    var onDismissed: (() -> Void)?
    private var didFireDismissed = false

    // Global + local Escape-key safety net so the popup is ALWAYS dismissible,
    // even if it renders off-screen, behind another window, or over the Dock.
    private var globalEscMonitor: Any?
    private var localEscMonitor: Any?

    // MARK: - Init

    override init() {
        super.init()
        buildPanel()
    }

    deinit {
        removeEscMonitors()
    }

    // MARK: - Public API

    static func show(anchor: CGRect, phase: Phase) -> SuggestionWindowController {
        let c = SuggestionWindowController()
        c.lastAnchor = anchor
        c.update(phase: phase)
        c.position(near: anchor)
        c.panel.orderFrontRegardless()
        c.installEscMonitors()
        NSLog("[Fluent] Popup shown, isVisible=\(c.panel.isVisible) frame=\(c.panel.frame)")
        return c
    }

    /// Force-dismiss the popup from anywhere (e.g. clicking the menu bar icon).
    func forceDismiss() {
        didReject()
    }

    private func installEscMonitors() {
        removeEscMonitors()
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.didReject() }   // 53 = Escape
        }
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.didReject(); return nil }
            return event
        }
    }

    private func removeEscMonitors() {
        if let m = globalEscMonitor { NSEvent.removeMonitor(m); globalEscMonitor = nil }
        if let m = localEscMonitor { NSEvent.removeMonitor(m); localEscMonitor = nil }
    }

    func update(phase: Phase) {
        switch phase {
        case .loading(let mode):
            loadingLabel.stringValue = modeTitle(mode)
            spinner.startAnimation(nil)
            swap(show: loadingView, hide: [resultView, errorView])

        case .result(let response, let onAccept, let onReject):
            spinner.stopAnimation(nil)
            acceptHandler = onAccept
            rejectHandler = onReject
            modeLabel.stringValue = "✦ Fluent"
            correctedLabel.stringValue = response.corrected
            applyWidth(idealWidth(for: response.corrected))
            updateCorrectedTextHeight()
            swap(show: resultView, hide: [loadingView, errorView])

        case .error(let msg, let isAuth, let onOpen):
            spinner.stopAnimation(nil)
            errorMsgLabel.stringValue = msg
            settingsButton.isHidden = !isAuth
            settingsHandler = onOpen
            applyWidth(idealWidth(for: msg))
            swap(show: errorView, hide: [loadingView, resultView])
        }

        sizeToContent()
        if let anchor = lastAnchor { position(near: anchor) }
    }

    /// Estimates the natural (unwrapped) width of the widest line in `text` at
    /// the corrected-text font, clamped to `minWidth...maxWidth`. Explicit
    /// newlines still break lines even with an unbounded measuring width, so
    /// this reflects the longest line, not the whole blob laid out on one row.
    private func idealWidth(for text: String) -> CGFloat {
        guard !text.isEmpty else { return minWidth }
        let font = NSFont.systemFont(ofSize: 13)
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        let horizontalPadding: CGFloat = 28
        return max(minWidth, min(bounding.width + horizontalPadding, maxWidth))
    }

    /// Applies a new panel width: updates the root/scroll-view width constraints
    /// and the wrapping labels' layout width to match.
    private func applyWidth(_ width: CGFloat) {
        currentWidth = width
        rootWidthConstraint.constant = width
        correctedScrollWidthConstraint.constant = width - 28
        correctedLabel.preferredMaxLayoutWidth = width - 28
        errorMsgLabel.preferredMaxLayoutWidth = width - 28
    }

    func close() {
        panel.orderOut(nil)
    }

    // MARK: - Build panel

    private func buildPanel() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: currentWidth, height: 60),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovable = true
        // Borderless panels have no title bar to drag by, so dragging from
        // anywhere on the panel's background is the only way to move it.
        panel.isMovableByWindowBackground = true
        // `.resizable` gives the standard edge/corner drag cursors for free;
        // bound how far the user can shrink/grow it.
        panel.contentMinSize = NSSize(width: minWidth, height: 60)
        panel.contentMaxSize = NSSize(width: 900, height: 800)
        panel.delegate = self

        let root = RoundedView(cornerRadius: 12)
        root.wantsLayer = true
        root.layer?.cornerRadius = 12
        root.layer?.masksToBounds = true
        if #available(macOS 14.0, *) {
            root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        } else {
            root.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }

        buildLoadingView()
        buildResultView()
        buildErrorView()

        let phaseStack = NSStackView(views: [loadingView, resultView, errorView])
        phaseStack.orientation = .vertical
        phaseStack.spacing = 0
        phaseStack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(phaseStack)
        panel.contentView = root

        rootWidthConstraint = root.widthAnchor.constraint(equalToConstant: currentWidth)
        NSLayoutConstraint.activate([
            phaseStack.topAnchor.constraint(equalTo: root.topAnchor),
            phaseStack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            phaseStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            phaseStack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            rootWidthConstraint,
        ])
    }

    // MARK: - Loading view

    private func buildLoadingView() {
        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true

        loadingLabel = chip("Fluent is thinking…", color: .secondaryLabelColor)

        loadingDismissButton = popoverButton(title: "Cancel", action: #selector(didReject))
        loadingDismissButton.keyEquivalent = "\u{1B}"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [spinner, loadingLabel, spacer, loadingDismissButton])
        row.orientation = .horizontal
        row.spacing = 6
        row.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        loadingView = row
    }

    // MARK: - Result view

    private func buildResultView() {
        modeLabel = chip("✦ Fluent", color: .secondaryLabelColor)

        correctedLabel = NSTextField(wrappingLabelWithString: "")
        correctedLabel.font = .systemFont(ofSize: 13)
        correctedLabel.textColor = .labelColor
        correctedLabel.maximumNumberOfLines = 0
        correctedLabel.lineBreakMode = .byWordWrapping
        correctedLabel.isSelectable = true
        correctedLabel.preferredMaxLayoutWidth = currentWidth - 28
        correctedLabel.translatesAutoresizingMaskIntoConstraints = false

        correctedScrollView = NSScrollView()
        correctedScrollView.hasVerticalScroller = true
        correctedScrollView.autohidesScrollers = true
        correctedScrollView.drawsBackground = false
        correctedScrollView.borderType = .noBorder
        correctedScrollView.translatesAutoresizingMaskIntoConstraints = false
        correctedScrollView.documentView = correctedLabel

        correctedLabelHeightConstraint = correctedLabel.heightAnchor.constraint(equalToConstant: 20)
        correctedScrollHeightConstraint = correctedScrollView.heightAnchor.constraint(equalToConstant: 20)

        NSLayoutConstraint.activate([
            correctedLabel.leadingAnchor.constraint(equalTo: correctedScrollView.contentView.leadingAnchor),
            correctedLabel.trailingAnchor.constraint(equalTo: correctedScrollView.contentView.trailingAnchor),
            correctedLabel.topAnchor.constraint(equalTo: correctedScrollView.contentView.topAnchor),
            correctedLabelHeightConstraint,
            correctedScrollHeightConstraint,
        ])

        let divider = NSBox()
        divider.boxType = .separator

        rejectButton = popoverButton(title: "Dismiss", action: #selector(didReject))
        rejectButton.keyEquivalent = "\u{1B}"

        acceptButton = popoverButton(title: "✓  Accept", action: #selector(didAccept))
        acceptButton.keyEquivalent = "\r"
        acceptButton.keyEquivalentModifierMask = .command
        acceptButton.contentTintColor = .systemBlue

        let buttonRow = NSStackView(views: [rejectButton, NSView(), acceptButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 0
        buttonRow.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        (buttonRow.views[1] as NSView).setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [modeLabel, correctedScrollView, divider, buttonRow])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 0, right: 14)
        // Give the label some bottom breathing room before divider
        stack.setCustomSpacing(8, after: modeLabel)
        stack.setCustomSpacing(10, after: correctedScrollView)
        stack.setCustomSpacing(0, after: divider)

        correctedScrollWidthConstraint = correctedScrollView.widthAnchor.constraint(equalToConstant: currentWidth - 28)
        NSLayoutConstraint.activate([correctedScrollWidthConstraint])

        resultView = stack
    }

    /// Recomputes the corrected-text label's natural height and clamps the
    /// scroll view to `maxCorrectedTextHeight`, so short text fits snugly and
    /// long text scrolls instead of being truncated or blowing up the popup.
    /// Must run after `applyWidth`, since height depends on the current width.
    private func updateCorrectedTextHeight() {
        let naturalHeight = correctedLabel.sizeThatFits(
            NSSize(width: currentWidth - 28, height: .greatestFiniteMagnitude)
        ).height
        correctedLabelHeightConstraint.constant = naturalHeight
        correctedScrollHeightConstraint.constant = min(naturalHeight, maxCorrectedTextHeight)
    }

    // MARK: - Error view

    private func buildErrorView() {
        errorMsgLabel = NSTextField(wrappingLabelWithString: "")
        errorMsgLabel.font = .systemFont(ofSize: 12)
        errorMsgLabel.textColor = .systemRed
        errorMsgLabel.maximumNumberOfLines = 4
        errorMsgLabel.preferredMaxLayoutWidth = currentWidth - 28

        settingsButton = popoverButton(title: "Open Settings", action: #selector(didOpenSettings))
        settingsButton.contentTintColor = .systemBlue

        errorDismissButton = popoverButton(title: "Dismiss", action: #selector(didReject))
        errorDismissButton.keyEquivalent = "\u{1B}"

        let divider = NSBox()
        divider.boxType = .separator

        let buttonRow = NSStackView(views: [errorDismissButton, NSView(), settingsButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 0
        buttonRow.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        (buttonRow.views[1] as NSView).setContentHuggingPriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [errorMsgLabel, divider, buttonRow])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 0, right: 14)
        stack.setCustomSpacing(10, after: errorMsgLabel)
        stack.setCustomSpacing(0, after: divider)

        errorView = stack
    }

    // MARK: - Sizing

    private func sizeToContent() {
        panel.contentView?.layoutSubtreeIfNeeded()
        let h = panel.contentView?.fittingSize.height ?? 60
        panel.setContentSize(NSSize(width: currentWidth, height: max(h, 44)))
    }

    // MARK: - Positioning

    /// Place the popover near the given anchor point.
    ///
    /// `anchor` is in the window server's global coordinate space: origin at the
    /// top-left of the *primary* screen (screens.first, i.e. the one with the menu
    /// bar), Y increasing downward — the same space used by both AX geometry and
    /// `CGWindowListCopyWindowInfo`. This is NOT the same as `NSScreen.main` (which
    /// tracks the key-window's screen), so we always flip using screens.first.
    private func position(near anchor: CGRect) {
        guard let primaryScreen = NSScreen.screens.first else { panel.center(); return }
        let primaryH = primaryScreen.frame.height
        let panelH = panel.frame.height
        let gap: CGFloat = 8

        // Anchor's vertical center, flipped into Cocoa's bottom-left-origin space.
        let anchorMidY = anchor.origin.y + anchor.size.height / 2
        let cocoaMidY = primaryH - anchorMidY
        let cocoaX = anchor.origin.x + (anchor.size.width - currentWidth) / 2

        // Find which physical screen actually contains this point, so we clamp
        // against the correct bounds on multi-monitor setups.
        let testPoint = NSPoint(x: anchor.origin.x, y: cocoaMidY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(testPoint) }) ?? primaryScreen
        let bounds = screen.visibleFrame

        // Center the popup vertically around the anchor point.
        var panelY = cocoaMidY - panelH / 2
        panelY = max(bounds.minY + gap, min(panelY, bounds.maxY - panelH - gap))

        var panelX = cocoaX
        panelX = max(bounds.minX + gap, min(panelX, bounds.maxX - currentWidth - gap))

        NSLog("[Fluent] Positioning popup at (\(panelX), \(panelY)) on screen \(screen.frame)")
        panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
    }

    // MARK: - Helpers

    private func swap(show: NSView, hide: [NSView]) {
        show.isHidden = false
        hide.forEach { $0.isHidden = true }
    }

    private func modeTitle(_ mode: String) -> String {
        switch mode {
        case "fixit":   return "Fixing grammar…"
        case "rewrite": return "Rewriting…"
        case "formal":  return "Making formal…"
        case "casual":  return "Making casual…"
        default:        return "Thinking…"
        }
    }

    private func chip(_ text: String, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: 11)
        f.textColor = color
        return f
    }

    private func popoverButton(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .inline
        btn.isBordered = false
        btn.font = .systemFont(ofSize: 12)
        return btn
    }

    // MARK: - Actions

    @objc private func didAccept() { finish(calling: acceptHandler) }
    @objc private func didReject() { finish(calling: rejectHandler) }
    @objc private func didOpenSettings() { finish(calling: settingsHandler) }

    /// Single funnel for every dismissal path. Guarantees `onDismissed` fires
    /// exactly once no matter which button (or Escape, or system close) triggered it.
    private func finish(calling specificHandler: (() -> Void)?) {
        removeEscMonitors()
        close()
        specificHandler?()
        if !didFireDismissed {
            didFireDismissed = true
            onDismissed?()
        }
        acceptHandler = nil
        rejectHandler = nil
        settingsHandler = nil
        onDismissed = nil
    }

    // MARK: - NSWindowDelegate (system close, e.g. if a title bar is ever added back)

    func windowWillClose(_ notification: Notification) {
        finish(calling: rejectHandler)
    }

    /// Fires continuously while the user drags an edge/corner to resize the
    /// panel. The width/height constraints below are otherwise driven by our
    /// own auto-sizing code (`applyWidth`/`updateCorrectedTextHeight`), which
    /// would fight a manual drag if left stale — so on every tick we resync
    /// them to the frame the user is actively dragging to, and re-wrap the
    /// corrected-text label for the new width.
    func windowDidResize(_ notification: Notification) {
        let newWidth = panel.frame.width
        currentWidth = newWidth
        rootWidthConstraint.constant = newWidth
        errorMsgLabel.preferredMaxLayoutWidth = newWidth - 28

        guard !resultView.isHidden else { return }

        panel.contentView?.layoutSubtreeIfNeeded()
        let totalFitting = panel.contentView?.fittingSize.height ?? panel.frame.height
        let othersHeight = totalFitting - correctedScrollHeightConstraint.constant

        correctedScrollWidthConstraint.constant = newWidth - 28
        correctedLabel.preferredMaxLayoutWidth = newWidth - 28
        let naturalTextHeight = correctedLabel.sizeThatFits(
            NSSize(width: newWidth - 28, height: .greatestFiniteMagnitude)
        ).height
        correctedLabelHeightConstraint.constant = naturalTextHeight
        correctedScrollHeightConstraint.constant = max(40, panel.frame.height - othersHeight)
    }
}

// MARK: - Helpers

private final class RoundedView: NSView {
    let cornerRadius: CGFloat
    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateLayer() {
        layer?.cornerRadius = cornerRadius
        if #available(macOS 14.0, *) {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        } else {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
    }
}
