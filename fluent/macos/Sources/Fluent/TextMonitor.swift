import Cocoa
import ApplicationServices
import CoreGraphics

typealias TriggerCallback = (
    _ text: String,
    _ mode: String,
    _ axElement: AXUIElement,
    _ anchorFrame: CGRect   // anchor rect in AX/window-server screen coords (top-left origin)
) -> Void

/// Monitors all key events via a CGEventTap.
///
/// Detection is gated by a single `isPopupActive` flag rather than by comparing
/// field text: comparing text is fragile because `TextInjector` isn't guaranteed
/// to succeed (many web-based text areas silently reject programmatic AX value
/// changes), so relying on "does the field now match what we injected" can get
/// permanently stuck if that assumption is ever wrong.
///
/// Instead, the flag is set the instant a trigger fires, and cleared by exactly
/// one call — `reset()` — which the app calls from the single guaranteed
/// dismissal callback of the suggestion popup (accept, reject, settings, or
/// escape). This makes the state machine trivial to reason about: a popup is
/// either active (ignore all further triggers) or not (ready for the next one).
final class TextMonitor {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    /// Fired when a trigger suffix is detected while no popup is currently active.
    var onTrigger: TriggerCallback?

    /// True from the moment a trigger fires until `reset()` is called.
    private var isPopupActive = false

    private let triggers: [(suffix: String, mode: String)] = [
        ("/fixit",   "fixit"),
        ("/rewrite", "rewrite"),
        ("/formal",  "formal"),
        ("/casual",  "casual"),
    ]

    func start() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<TextMonitor>.fromOpaque(refcon).takeUnretainedValue()
                if type == .keyDown { monitor.handleKeyDown(event) }
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[Fluent] CGEventTap creation failed — check Accessibility permissions")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[Fluent] TextMonitor started")
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    /// The ONE place popup state gets cleared. Call this from the suggestion
    /// popup's guaranteed dismissal callback — regardless of whether the user
    /// accepted, rejected, opened settings, or pressed Escape.
    func reset() {
        isPopupActive = false
        NSLog("[Fluent] TextMonitor reset — ready for next trigger")
    }

    // MARK: - Key handling

    private func handleKeyDown(_ event: CGEvent) {
        guard !isPopupActive else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.checkFocusedElement()
        }
    }

    private func checkFocusedElement() {
        guard !isPopupActive else { return }
        guard let (element, value) = focusedTextAndElement() else { return }
        guard !value.isEmpty else { return }

        let lower = value.lowercased()
        for (suffix, mode) in triggers {
            guard lower.hasSuffix(suffix) else { continue }

            let stripped = String(value.prefix(value.count - suffix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stripped.isEmpty else { return }

            isPopupActive = true
            let anchor = resolveAnchor(for: element)
            NSLog("[Fluent] Trigger detected: mode=\(mode) text=\(stripped.prefix(40)) anchor=\(anchor)")
            onTrigger?(stripped, mode, element, anchor)
            return
        }
    }

    // MARK: - AX helpers

    private func focusedTextAndElement() -> (AXUIElement, String)? {
        let system = AXUIElementCreateSystemWide()
        var focusedApp: AnyObject?
        let appStatus = AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focusedApp)
        guard appStatus == .success else {
            logSkip("no focused application (status=\(appStatus.rawValue))")
            return nil
        }

        var focusedEl: AnyObject?
        let elStatus = AXUIElementCopyAttributeValue(
            focusedApp as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusedEl
        )
        guard elStatus == .success, let focusedElUnwrapped = focusedEl else {
            logSkip("no focused UI element in app (status=\(elStatus.rawValue))")
            return nil
        }

        let el = focusedElUnwrapped as! AXUIElement

        var role: AnyObject?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        let r = role as? String ?? "?"
        guard r == kAXTextFieldRole as String || r == kAXTextAreaRole as String || r == "AXComboBox" else {
            logSkip("focused element role='\(r)' is not a text field")
            return nil
        }

        var val: AnyObject?
        let valStatus = AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &val)
        guard valStatus == .success, let text = val as? String else {
            logSkip("focused text field has no readable value (status=\(valStatus.rawValue))")
            return nil
        }
        return (el, text)
    }

    // Throttled so we don't spam the log on every single keystroke while idle.
    private var lastSkipReason: String?
    private func logSkip(_ reason: String) {
        guard reason != lastSkipReason else { return }
        lastSkipReason = reason
        NSLog("[Fluent] focusedTextAndElement: \(reason)")
    }

    // MARK: - Anchor resolution (simple, two-step)

    /// Resolves an anchor rect for positioning the popup:
    ///  1. Exact caret bounds when the app supports it (mostly native Cocoa text fields).
    ///  2. The focused element's own frame (`kAXPositionAttribute`/`kAXSizeAttribute`) —
    ///     supported much more widely than caret-range bounds, including by most
    ///     web/Electron AX bridges (Chrome, Slack, Discord, VS Code, etc.), so this
    ///     still anchors to the actual field even when strategy 1 isn't available.
    ///  3. Otherwise, the frontmost window's on-screen bounds from the window server
    ///     (`CGWindowListCopyWindowInfo`) — this works for *every* app, but only
    ///     approximates "near the input" with the window's bottom-center, so it's a
    ///     last resort, not a substitute for strategy 2.
    private func resolveAnchor(for element: AXUIElement) -> CGRect {
        // Guard against degenerate rects some apps return (e.g. a zero-size rect
        // sitting at a garbage/uninitialized position) — only trust a rect that
        // actually has real width AND height.
        if let rect = caretBounds(for: element), rect.width > 0, rect.height > 0 {
            NSLog("[Fluent] anchor strategy=caretBounds rect=\(rect)")
            return rect
        }

        if let rect = elementFrame(for: element), rect.width > 0, rect.height > 0 {
            NSLog("[Fluent] anchor strategy=elementFrame rect=\(rect)")
            return rect
        }

        if let windowFrame = frontmostWindowFrame(), windowFrame.width > 0, windowFrame.height > 0 {
            NSLog("[Fluent] anchor strategy=frontmostWindowFrame rawFrame=\(windowFrame)")
            // Anchor near the bottom-center of the window — most text-input UIs
            // (chat apps, comment boxes, compose windows) place the input there.
            let anchorWidth = min(windowFrame.width - 48, 400)
            let x = windowFrame.origin.x + (windowFrame.width - anchorWidth) / 2
            let y = windowFrame.origin.y + windowFrame.height - 100
            return CGRect(x: x, y: y, width: anchorWidth, height: 20)
        }

        NSLog("[Fluent] anchor strategy=screenCenter — window bounds unavailable")
        let screen = NSScreen.screens.first?.frame ?? .zero
        return CGRect(x: screen.midX - 150, y: screen.midY, width: 300, height: 20)
    }

    /// Exact insertion-point bounds via the selected-text-range parameterised attribute.
    private func caretBounds(for element: AXUIElement) -> CGRect? {
        var rangeVal: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeVal) == .success,
              let axRange = rangeVal
        else { return nil }

        var boundsVal: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, axRange, &boundsVal
        ) == .success, let bv = boundsVal else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bv as! AXValue, .cgRect, &rect) else { return nil }
        return rect
    }

    /// The focused element's own on-screen frame, via `kAXPositionAttribute` +
    /// `kAXSizeAttribute`. Both are in the same top-left-origin screen coordinate
    /// space as `caretBounds`/`CGWindowListCopyWindowInfo`.
    private func elementFrame(for element: AXUIElement) -> CGRect? {
        var positionVal: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionVal) == .success,
              let pv = positionVal
        else { return nil }

        var sizeVal: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeVal) == .success,
              let sv = sizeVal
        else { return nil }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(pv as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sv as! AXValue, .cgSize, &size)
        else { return nil }

        return CGRect(origin: origin, size: size)
    }

    /// The frontmost app's largest on-screen window, straight from the window server.
    /// Bounds are already in the same top-left-origin, primary-screen-relative
    /// coordinate space as AX geometry, so no app-side AX support is required.
    private func frontmostWindowFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier

        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: AnyObject]] else { return nil }

        var best: CGRect?
        for info in infoList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }

            let rect = CGRect(
                x: boundsDict["X"] ?? 0, y: boundsDict["Y"] ?? 0,
                width: boundsDict["Width"] ?? 0, height: boundsDict["Height"] ?? 0
            )
            // Skip tiny helper/tooltip windows; keep the largest real window.
            if rect.width > 200, rect.height > 100, (best == nil || rect.width * rect.height > best!.width * best!.height) {
                best = rect
            }
        }
        return best
    }
}
