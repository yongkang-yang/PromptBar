// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// The panel's content: a header, one card per section, and a footer that
/// names the keys.
struct ResultView: View {
    @ObservedObject var model: ResultModel
    let actions: ResultActions

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, Metrics.panelPadding + 4)
                .padding(.top, Metrics.panelPadding)
                .padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let error = model.loadError {
                        ErrorCard(title: "Could not process text", message: error)
                    } else if model.isReading {
                        Placeholder(text: model.mode == .ocr ? "Recognizing text…" : "Reading selection…")
                    }
                    ForEach(model.sections) { section in
                        SectionCard(section: section, index: section.id, actions: actions)
                    }
                }
                .padding(.horizontal, Metrics.panelPadding)
                .padding(.bottom, Metrics.panelPadding)
            }
            .scrollIndicators(.automatic)
            footer
        }
        .frame(width: Metrics.panelWidth)
        .frame(minHeight: 200, maxHeight: .infinity, alignment: .top)
        .glassSurface(in: RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous),
                      fallback: .regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(model.mode.title)
                .font(.system(size: 13, weight: .semibold))
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            Spacer()
            GlassGroup {
                HStack(spacing: 6) {
                    if model.mode != .ocr {
                        GlassIconButton(symbol: "arrow.clockwise", help: "Read Selection Again (↩)", action: actions.refresh)
                    }
                    GlassIconButton(symbol: "gearshape", help: "Settings (⌘,)", action: actions.openSettings)
                    GlassIconButton(symbol: "xmark", help: "Close (Esc)", action: actions.close)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if model.mode == .ocr {
                KeyHint(keys: "↩", label: "Paste \(model.sections.first?.section.heading ?? "")")
            } else {
                KeyHint(keys: "↩", label: "Refresh")
                KeyHint(keys: "⌘↩", label: "Paste \(model.sections.first?.section.heading ?? "Result")")
            }
            if model.sections.count > 1 {
                KeyHint(keys: "⌘1–\(model.sections.count)", label: "Paste Section")
            }
            Spacer()
            KeyHint(keys: "esc", label: "Close")
        }
        .padding(.horizontal, Metrics.panelPadding + 4)
        .padding(.vertical, 9)
        .background(alignment: .top) { Divider().opacity(0.5) }
    }
}

/// What the buttons in the panel do; the window controller supplies them.
struct ResultActions {
    var refresh: () -> Void
    var paste: (Int) -> Void
    var copy: (Int) -> Void
    var openSettings: () -> Void
    var close: () -> Void
}

private struct SectionCard: View {
    let section: ResultModel.Section
    let index: Int
    let actions: ResultActions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(section.section.heading)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if section.text != nil {
                    GlassGroup {
                        HStack(spacing: 6) {
                            GlassPillButton(title: "Copy", symbol: "doc.on.doc") { actions.copy(index) }
                            GlassPillButton(title: "Paste", symbol: "arrow.down.doc", shortcut: "⌘\(index + 1)") {
                                actions.paste(index)
                            }
                        }
                    }
                }
            }
            if let error = section.error {
                Text("Could not generate this section: \(error)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .italic()
                    .textSelection(.enabled)
            } else if let text = section.text {
                if section.section.task == nil {
                    // The source text as recognized: line breaks and any
                    // Markdown-like characters shown exactly as they are.
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    MarkdownView(text)
                }
            } else {
                Placeholder(text: "Generating…")
            }
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct ErrorCard: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

private struct Placeholder: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct KeyHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(label)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }
}
