// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import PromptBarKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let results = ResultWindow()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            // The bare symbol draws at the menu bar's small default; bake the size in.
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            button.image = NSImage(systemSymbolName: "character.bubble", accessibilityDescription: "PromptBar")?
                .withSymbolConfiguration(configuration)
            button.image?.isTemplate = true
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        results.onRefresh = { [weak self] in
            guard let self else { return }
            self.readSelection(self.results.model.mode)
        }
        results.onOpenSettings = { [weak self] in self?.openSettings(nil) }

        let hotKeys = HotKeyCenter.shared
        hotKeys.register(Command.selectionAssistant.rawValue) { [weak self] in self?.readSelection(.selection) }
        hotKeys.register(Command.friendlyReply.rawValue) { [weak self] in self?.readSelection(.reply) }
        hotKeys.register(Command.ocrTranslate.rawValue) { [weak self] in self?.ocrTranslate() }

        // First run: nothing works without a model, so start in Settings.
        if AppSettings.model.apiKey.isEmpty {
            openSettings(nil)
        }
    }

    // MARK: - Commands

    /// The app whose selection to read. While our own panel or Settings is
    /// in front, that's still the app the last command read from.
    private func currentTarget() -> NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return results.target
        }
        return front
    }

    /// Selection Assistant and Friendly Reply. Every press reads the
    /// selection afresh, so a result on screen is never stale.
    private func readSelection(_ mode: ResultModel.Mode) {
        let target = currentTarget()
        results.target = target
        results.model.beginReading(mode == .ocr ? .selection : mode)
        Task {
            do {
                let text = try await SelectionReader.read(from: target) { self.results.stepAside() }
                let plan = mode == .reply ? SectionPlan.reply : SectionPlan.forSelection(text)
                results.model.run(plan, text: text)
            } catch {
                results.model.fail(error.localizedDescription)
            }
            results.show()
        }
    }

    private func ocrTranslate() {
        let target = currentTarget()
        results.close()
        guard Permissions.hasScreenRecording else {
            Permissions.requestScreenRecording()
            HUD.shared.show("OCR Translate needs Screen Recording access. Turn it on in System Settings → Privacy & Security.",
                            style: .failure)
            return
        }
        Task {
            guard let file = await ScreenText.captureRegion() else {
                HUD.shared.show("Capture cancelled", style: .failure)
                return
            }
            defer { ScreenText.discard(file) }
            results.target = target
            HUD.shared.show("Recognizing text…", style: .progress)
            do {
                let text = try await ScreenText.recognize(file)
                HUD.shared.hide()
                results.model.beginReading(.ocr)
                if text.isEmpty {
                    results.model.fail("No text was recognized in the selected area.")
                } else {
                    results.model.run(SectionPlan.forRecognizedText(text), text: text)
                }
            } catch {
                // Local recognition failed outright (not merely "no text
                // found"), so the model reads the image itself.
                results.model.beginReading(.ocr)
                guard let data = try? Data(contentsOf: file), data.count <= 10 * 1024 * 1024 else {
                    HUD.shared.hide()
                    results.model.fail("Image is too large. Select a smaller area (under 10 MB).")
                    results.show()
                    return
                }
                HUD.shared.show("Local OCR failed — reading image with your model…")
                results.model.run(SectionPlan.ocrImage, text: "",
                                  imageDataURL: "data:image/png;base64,\(data.base64EncodedString())")
            }
            results.show()
        }
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        switch Command(rawValue: sender.representedObject as? String ?? "") {
        case .selectionAssistant: readSelection(.selection)
        case .friendlyReply: readSelection(.reply)
        case .ocrTranslate: ocrTranslate()
        case nil: break
        }
    }

    @objc func openSettings(_ sender: Any?) {
        results.close()
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menus

    /// Built each time it opens, so the shortcuts beside the commands are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for command in Command.allCases {
            let item = NSMenuItem(title: command.title, action: #selector(runCommand(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command.rawValue
            item.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil)
            if let shortcut = HotKeyCenter.shared.shortcuts[command.rawValue], let key = shortcut.menuKeyEquivalent {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = shortcut.flags
            }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(withTitle: "Quit PromptBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// Accessory apps have no visible menu bar, but the main menu still routes
    /// key equivalents; without it ⌘C, ⌘V and ⌘A don't work in Settings.
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: "Quit PromptBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}
