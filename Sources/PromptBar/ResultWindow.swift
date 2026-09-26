// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// The floating result panel. It is non-activating, like Spotlight: it takes
/// the keyboard without making the app you were in inactive, so pasting goes
/// straight back into it.
@MainActor
final class ResultWindow: NSObject, NSWindowDelegate {
    let model = ResultModel()
    /// The app whose selection was read, and where Paste goes.
    var target: NSRunningApplication?
    var onRefresh: () -> Void = {}
    var onOpenSettings: () -> Void = {}

    private lazy var panel: KeyPanel = makePanel()
    /// Set while the panel steps aside for a simulated ⌘C, so losing key
    /// status then doesn't close it.
    private var isSteppingAside = false

    var isVisible: Bool { panel.isVisible }

    func show() {
        isSteppingAside = false
        if !panel.isVisible {
            position()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
    }

    /// Hides the panel for a moment without closing it.
    func stepAside() {
        guard panel.isVisible else { return }
        isSteppingAside = true
        panel.orderOut(nil)
    }

    func close() {
        isSteppingAside = false
        model.cancel()
        panel.orderOut(nil)
    }

    func paste(_ index: Int) {
        guard let text = model.text(at: index) else {
            NSSound.beep()
            return
        }
        close()
        Keystroke.paste(text, into: target)
    }

    func copy(_ index: Int) {
        guard let text = model.text(at: index) else { return }
        Clipboard.copy(text)
        HUD.shared.show("Copied \(model.sections[index].section.heading)")
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else dismisses the panel, as Raycast's window did.
        if !isSteppingAside { close() }
    }

    private func position() {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let height = min(600, visible.height * 0.75)
        panel.setContentSize(NSSize(width: Metrics.panelWidth, height: height))
        let x = visible.midX - Metrics.panelWidth / 2
        let top = visible.maxY - visible.height * 0.16
        panel.setFrameOrigin(NSPoint(x: x, y: top - height))
    }

    private func makePanel() -> KeyPanel {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: 560),
                             styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                             backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        let actions = ResultActions(
            refresh: { [weak self] in self?.onRefresh() },
            paste: { [weak self] in self?.paste($0) },
            copy: { [weak self] in self?.copy($0) },
            openSettings: { [weak self] in self?.onOpenSettings() },
            close: { [weak self] in self?.close() }
        )
        panel.contentView = NSHostingView(rootView: ResultView(model: model, actions: actions))
        panel.roundCorners(Metrics.panelRadius)
        panel.onKey = { [weak self] event in self?.handle(event) ?? false }
        return panel
    }

    /// ↩ reads the selection again (⌘↩ pastes) — or, for OCR, where the text
    /// came from a fresh capture, ↩ pastes. ⌘1–9 paste a section.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch Int(event.keyCode) {
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if flags == .command || model.mode == .ocr {
                paste(0)
            } else if flags.isEmpty {
                onRefresh()
            } else {
                return false
            }
            return true
        case kVK_Escape:
            close()
            return true
        default:
            break
        }
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if let digit = Int(key), (1...9).contains(digit) {
            paste(digit - 1)
            return true
        }
        switch key {
        case "r" where model.mode != .ocr:
            onRefresh()
        case ",":
            onOpenSettings()
        case "w":
            close()
        default:
            return false
        }
        return true
    }
}

final class KeyPanel: NSPanel {
    var onKey: (NSEvent) -> Bool = { _ in false }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Keys are handled before the hosted views see them, so selectable
    /// text can't swallow ↩ or Esc.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey(event) { return }
        super.sendEvent(event)
    }
}
