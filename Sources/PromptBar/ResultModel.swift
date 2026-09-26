// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import PromptBarKit

/// What the result panel is showing, and the requests that fill it.
@MainActor
final class ResultModel: ObservableObject {
    enum Mode: Equatable {
        case selection, reply, ocr

        var title: String {
            switch self {
            case .selection: "Selection Assistant"
            case .reply: "Friendly Reply"
            case .ocr: "OCR Translate"
            }
        }
    }

    struct Section: Identifiable {
        let id: Int
        let section: ResultSection
        var text: String?
        var error: String?

        var isLoading: Bool { text == nil && error == nil }
    }

    @Published private(set) var mode: Mode = .selection
    @Published private(set) var sections: [Section] = []
    /// Set when there is nothing to run: no selection, no permission, no text
    /// in the screenshot.
    @Published private(set) var loadError: String?
    @Published private(set) var isReading = false

    private let client = ChatClient()
    private var work: Task<Void, Never>?

    var isLoading: Bool { isReading || sections.contains(where: \.isLoading) }

    /// The first section that has a result; ⌘↵ pastes it.
    var primaryText: String? { sections.first?.text }

    func text(at index: Int) -> String? {
        sections.indices.contains(index) ? sections[index].text : nil
    }

    func beginReading(_ mode: Mode) {
        work?.cancel()
        self.mode = mode
        sections = []
        loadError = nil
        isReading = true
    }

    func fail(_ message: String) {
        work?.cancel()
        isReading = false
        sections = []
        loadError = message
    }

    /// Runs every section at once and shows each as it arrives.
    func run(_ plan: [ResultSection], text: String, imageDataURL: String? = nil) {
        work?.cancel()
        isReading = false
        loadError = nil
        sections = plan.enumerated().map { index, section in
            Section(id: index, section: section, text: section.task == nil ? text : nil)
        }
        let settings = AppSettings.model
        let client = self.client
        work = Task { [weak self] in
            await withTaskGroup(of: (Int, String?, String?).self) { group in
                for (index, section) in plan.enumerated() {
                    guard let task = section.task else { continue }
                    group.addTask {
                        do {
                            let output = try await client.generate(task, text: text, imageDataURL: imageDataURL, settings: settings)
                            return (index, output, nil)
                        } catch {
                            return (index, nil, error.localizedDescription)
                        }
                    }
                }
                for await (index, output, error) in group {
                    guard !Task.isCancelled, let self else { return }
                    self.sections[index].text = output
                    self.sections[index].error = output == nil ? (error ?? "Unexpected error") : nil
                }
            }
        }
    }

    func cancel() {
        work?.cancel()
        work = nil
    }
}
