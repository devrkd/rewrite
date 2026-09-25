import AppKit
import ApplicationServices
import CoreGraphics

/// Injects text into the currently focused field.
///
/// Many apps — especially Electron/web-based ones like Slack — don't properly
/// support `AXUIElementSetAttributeValue(kAXValueAttribute)`: the call reports
/// success but the app's internal (React/JS) state never actually changes, and
/// worse, it can silently drop the field's accessibility focus entirely. This
/// mirrors a well-known limitation hit by every macOS text-expander (Espanso,
/// Alfred, aText, etc.), and they all converge on the same fix: don't fight the
/// AX API — simulate the exact input a human would perform instead.
///
/// Strategy:
///  1. Try the AX value-set, then immediately read the value back to verify it
///     actually took effect (fast path — works for native Cocoa text fields).
///  2. If that didn't stick, fall back to staging the text on the clipboard and
///     simulating ⌘A (select all) + ⌘V (paste), which works for virtually any
///     editable field because it's the same path real keyboard input takes.
enum TextInjector {

    /// `AXUIElementSetAttributeValue`/`AXUIElementCopyAttributeValue` are
    /// synchronous, blocking IPC calls into the *target* app's process. If that
    /// app's AX-handling thread is busy or unresponsive (common with
    /// Electron/web apps), these calls can hang indefinitely. Fluent is
    /// single-threaded, so a hang here would freeze the same run loop that
    /// drives the trigger-detection event tap — permanently breaking the popup
    /// until the app is force-quit. To prevent that, the actual AX round-trips
    /// run on a background queue; only pasteboard/keyboard-event work (which
    /// touches AppKit state) hops back to the main thread.
    @discardableResult
    static func inject(text: String, into element: AXUIElement) -> Bool {
        DispatchQueue.global(qos: .userInitiated).async {
            AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, true as CFTypeRef)
            let usedFastPath = setViaAX(text: text, into: element)

            DispatchQueue.main.async {
                if usedFastPath {
                    NSLog("[Fluent] TextInjector: AX value-set verified — used fast path")
                } else {
                    NSLog("[Fluent] TextInjector: AX value-set did not stick — falling back to select-all + paste")
                    injectViaPaste(text: text)
                }
            }
        }
        return true
    }

    // MARK: - Fast path: direct AX value

    private static func setViaAX(text: String, into element: AXUIElement) -> Bool {
        let setStatus = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFTypeRef)
        guard setStatus == .success else {
            NSLog("[Fluent] TextInjector: AX set failed, status=\(setStatus.rawValue)")
            return false
        }

        // Verify it actually took effect — some apps report .success without
        // applying the change at all.
        var readBack: AnyObject?
        let readStatus = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &readBack)
        guard readStatus == .success, let current = readBack as? String, current == text else {
            NSLog("[Fluent] TextInjector: AX read-back mismatch (status=\(readStatus.rawValue))")
            return false
        }

        // Move the caret to the end.
        var range = CFRange(location: text.count, length: 0)
        if let axRange = AXValueCreate(.cfRange, &range) {
            AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
        }
        return true
    }

    // MARK: - Fallback path: simulate real keyboard input

    private static func injectViaPaste(text: String) {
        let pasteboard = NSPasteboard.general
        let savedItems = snapshotPasteboard(pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Select all existing content in the focused field, then paste over it —
        // exactly what a human would do. This works regardless of whether the
        // app supports programmatic AX value changes.
        postKeyCombo(keyCode: 0, flags: .maskCommand)   // Cmd+A
        usleep(40_000)
        postKeyCombo(keyCode: 9, flags: .maskCommand)   // Cmd+V

        // Give the paste time to land before restoring the user's clipboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            restorePasteboard(pasteboard, items: savedItems)
        }
    }

    private static func postKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    // MARK: - Clipboard preservation

    private static func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        pasteboard.writeObjects(items)
    }
}
