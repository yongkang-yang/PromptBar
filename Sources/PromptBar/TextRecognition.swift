// SPDX-License-Identifier: GPL-3.0-or-later
@preconcurrency import Dispatch
import Foundation
import PromptBarKit
import Vision

/// Screen capture and local text recognition for OCR Translate.
enum ScreenText {
    /// Runs the system's interactive region capture. nil when cancelled.
    static func captureRegion() async -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("promptbar-ocr-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("selection.png")
        _ = try? await run("/usr/sbin/screencapture", ["-i", "-s", "-x", "-t", "png", file.path], timeout: 120)
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        guard size > 0 else {
            try? FileManager.default.removeItem(at: directory)
            return nil
        }
        return file
    }

    static func discard(_ file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    /// Recognizes the text in an image with Vision, in a child copy of this
    /// executable. Vision keeps its recognition model (~100 MB) loaded for
    /// the life of the process, so running it in a process that exits right
    /// after hands that memory back instead of leaving it in the menu bar app.
    static func recognize(_ file: URL) async throws -> String {
        guard let executable = Bundle.main.executablePath else { throw PromptError("Recognition unavailable.") }
        // The first run after boot can take ~15 s while the system loads the
        // recognition model; later runs take well under a second.
        let output = try await run(executable, [recognizeFlag, file.path], timeout: 60)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let recognizeFlag = "--recognize-text"

    /// The child process's side of `recognize`: prints the text and exits.
    static func recognizeAndExit(path: String) -> Never {
        let request = VNRecognizeTextRequest()
        // Accurate is required: the fast level only reads Latin script.
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        let handler = VNImageRequestHandler(url: URL(fileURLWithPath: path))
        do {
            try handler.perform([request])
        } catch {
            FileHandle.standardError.write(Data(error.localizedDescription.utf8))
            exit(1)
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        FileHandle.standardOutput.write(Data(lines.joined(separator: "\n").utf8))
        exit(0)
    }

    private struct ProcessFailed: Error {}

    /// Runs a tool and returns its standard output; throws on a non-zero exit
    /// or when it outlives `timeout`.
    private static func run(_ path: String, _ arguments: [String], timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
            // Drain the pipe while the tool runs, so a long output can't fill
            // the pipe's buffer and stall it.
            DispatchQueue.global().async {
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                timer.cancel()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: String(decoding: data, as: UTF8.self))
                } else {
                    continuation.resume(throwing: ProcessFailed())
                }
            }
        }
    }
}
