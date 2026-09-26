// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import PromptBarKit

/// The model settings: the key in the keychain, the rest in preferences.
enum AppSettings {
    static let baseURLKey = "baseURL"
    static let modelKey = "model"
    static let apiKeyAccount = "apiKey"

    static var model: ModelSettings {
        ModelSettings(
            apiKey: Keychain.read(apiKeyAccount),
            baseURL: UserDefaults.standard.string(forKey: baseURLKey) ?? ModelSettings.defaultBaseURL,
            model: UserDefaults.standard.string(forKey: modelKey) ?? ""
        )
    }
}

enum Permissions {
    /// Reading another app's selection and pasting into it both need this.
    static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that leads to the Accessibility pane.
    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Reads the text selected in another app.
enum SelectionReader {
    static let noSelection = "Select text in an app, then run this command again."

    /// Asks the app's focused element through Accessibility first, which
    /// leaves the clipboard alone. Apps that don't expose their selection
    /// that way (many Electron and web views) get a simulated ⌘C instead,
    /// with the clipboard put back afterwards. `beforeCopy` runs just before
    /// that fallback, so a key window of ours can step aside first.
    static func read(from app: NSRunningApplication?, beforeCopy: () -> Void = {}) async throws -> String {
        guard Permissions.hasAccessibility else {
            Permissions.requestAccessibility()
            throw PromptError("PromptBar needs Accessibility access to read the selection. Turn it on in System Settings → Privacy & Security → Accessibility, then try again.")
        }
        if let app, let text = accessibilitySelection(pid: app.processIdentifier),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        beforeCopy()
        if let text = await copySelection(),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        throw PromptError(noSelection)
    }

    private static func accessibilitySelection(pid: pid_t) -> String? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.5)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success
        else { return nil }
        return selected as? String
    }

    private static func copySelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let saved = Clipboard.snapshot()
        let before = pasteboard.changeCount
        Keystroke.post(UInt16(kVK_ANSI_C), flags: .maskCommand)
        // The target app writes the pasteboard on its own schedule.
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 15_000_000)
            if pasteboard.changeCount != before { break }
        }
        guard pasteboard.changeCount != before else { return nil }
        let text = pasteboard.string(forType: .string)
        Clipboard.restore(saved)
        return text
    }
}

/// Copies of whatever was on the clipboard, so borrowing it is invisible.
enum Clipboard {
    typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]

    static func snapshot() -> Snapshot {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    static func restore(_ snapshot: Snapshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items = snapshot.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entries { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

enum Keystroke {
    /// Posts a key press with exactly `flags`, whatever keys the user is still
    /// holding from the shortcut that got us here.
    static func post(_ key: UInt16, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .privateState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Puts `text` on the clipboard and pastes it into `app`. The text stays
    /// on the clipboard afterwards, as it did with Raycast's Paste action.
    static func paste(_ text: String, into app: NSRunningApplication?) {
        Clipboard.copy(text)
        app?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            post(UInt16(kVK_ANSI_V), flags: .maskCommand)
        }
    }
}
