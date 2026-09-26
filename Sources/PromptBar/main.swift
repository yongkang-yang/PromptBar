// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

// OCR runs Vision in a short-lived copy of this executable; see ScreenText.recognize.
let arguments = CommandLine.arguments
if arguments.count == 3, arguments[1] == ScreenText.recognizeFlag {
    ScreenText.recognizeAndExit(path: arguments[2])
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
