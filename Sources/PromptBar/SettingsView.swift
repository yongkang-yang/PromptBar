// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Combine
import PromptBarKit
import ServiceManagement
import SwiftUI

/// A preferences window with toolbar tabs, like the system's own apps.
func makeSettingsWindow() -> NSWindow {
    let tabs = NSTabViewController()
    tabs.tabStyle = .toolbar
    tabs.addTabViewItem(settingsTab("Model", symbol: "cpu", ModelSettingsView()))
    tabs.addTabViewItem(settingsTab("Shortcuts", symbol: "keyboard", ShortcutsSettingsView()))
    tabs.addTabViewItem(settingsTab("General", symbol: "gearshape", GeneralSettingsView()))

    let window = NSWindow(contentViewController: tabs)
    window.styleMask = [.titled, .closable]
    window.toolbarStyle = .preference
    window.isReleasedWhenClosed = false
    window.center()
    return window
}

private func settingsTab<Content: View>(_ label: String, symbol: String, _ view: Content) -> NSTabViewItem {
    let controller = NSHostingController(rootView: view)
    controller.sizingOptions = .preferredContentSize
    controller.title = label
    let item = NSTabViewItem(viewController: controller)
    item.label = label
    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    return item
}

// MARK: - Model

private struct ModelSettingsView: View {
    @AppStorage(AppSettings.baseURLKey) private var baseURL = ModelSettings.defaultBaseURL
    @AppStorage(AppSettings.modelKey) private var model = ""
    @State private var apiKey = Keychain.read(AppSettings.apiKeyAccount)

    var body: some View {
        Form {
            Section {
                SecureField("API Key", text: $apiKey)
                    .onChange(of: apiKey) { _, value in Keychain.write(value, for: AppSettings.apiKeyAccount) }
                TextField("Base URL", text: $baseURL, prompt: Text(ModelSettings.defaultBaseURL))
                TextField("Model", text: $model, prompt: Text("e.g. openai/gpt-4.1-mini"))
            } footer: {
                Text("Any OpenAI-compatible endpoint works: OpenRouter, OpenAI directly, or a self-hosted gateway. Use the exact model ID from your provider. The key is kept in your login keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let problem {
                Section {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 300)
    }

    private var problem: String? {
        do {
            _ = try ChatClient.endpoint(for: baseURL)
        } catch {
            return error.localizedDescription
        }
        return nil
    }
}

// MARK: - Shortcuts

enum Command: String, CaseIterable {
    case selectionAssistant, friendlyReply, ocrTranslate

    var title: String {
        switch self {
        case .selectionAssistant: "Selection Assistant"
        case .friendlyReply: "Friendly Reply"
        case .ocrTranslate: "OCR Translate"
        }
    }

    var detail: String {
        switch self {
        case .selectionAssistant: "Word or phrase: Translate & Learn + Explain. Sentence or passage: Polish + Translate."
        case .friendlyReply: "A concise, polite reply to the selected text."
        case .ocrTranslate: "Select a screen region; its text is recognized on this Mac and translated."
        }
    }

    var symbol: String {
        switch self {
        case .selectionAssistant: "text.cursor"
        case .friendlyReply: "arrowshape.turn.up.left"
        case .ocrTranslate: "text.viewfinder"
        }
    }
}

private struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(Command.allCases, id: \.self) { command in
                    LabeledContent {
                        ShortcutRecorder(command.rawValue)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(command.title)
                            Text(command.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            } footer: {
                Text("Shortcuts work in every app. Pressing one again while results are showing reads the selection again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 300)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var hasAccessibility = Permissions.hasAccessibility
    @State private var hasScreenRecording = Permissions.hasScreenRecording
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle("Open PromptBar at login", isOn: Binding(get: { launchesAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section {
                PermissionRow(title: "Accessibility", detail: "Reads the selected text and pastes results.",
                              granted: hasAccessibility) {
                    Permissions.requestAccessibility()
                    Permissions.openPrivacyPane("Privacy_Accessibility")
                }
                PermissionRow(title: "Screen Recording", detail: "Lets OCR Translate capture a screen region.",
                              granted: hasScreenRecording) {
                    Permissions.requestScreenRecording()
                    Permissions.openPrivacyPane("Privacy_ScreenCapture")
                }
            } header: {
                Text("Permissions")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 300)
        .onReceive(timer) { _ in
            hasAccessibility = Permissions.hasAccessibility
            hasScreenRecording = Permissions.hasScreenRecording
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let grant: () -> Void

    var body: some View {
        LabeledContent {
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant…", action: grant)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
