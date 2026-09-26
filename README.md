# PromptBar

A native macOS menu bar app that translates, explains, polishes and replies to
the text you've selected — in any app — with your own model. It is the native
rewrite of the [Prompt](https://github.com/yongkang-yang/raycast-ai-prompt)
Raycast extension, without Raycast running underneath it.

## Commands

Each has its own global shortcut (Settings → Shortcuts) and a place in the menu
bar menu.

- **Selection Assistant** — the main entry point; bind it to a shortcut such as
  `⌥D`. Reads the current selection and decides whether it's a word/phrase or a
  sentence/passage:
  - Word or phrase → **Translate & Learn** (vocabulary mode: 中英对照, example
    sentences) + **Explain**.
  - Sentence or passage → **Polish** + **Translate**.
- **Friendly Reply** — a concise, polite reply to the selected text.
- **OCR Translate** — select a screen region; its text is recognized on this
  Mac and translated.
  - A word or phrase gets **Translate & Learn** + **Explain**, as a selection
    does.
  - A sentence or passage gets **Translate** + **Recognized Text** (the raw OCR
    output, ready to copy). Screenshot text is usually someone else's, so it is
    translated rather than polished.
  - Recognition uses the Vision framework (the engine behind Live Text) in
    accurate mode: offline, free, and it reads Chinese, English, Japanese and
    Korean. It runs in a short-lived child process, so its ~100 MB model is
    handed back as soon as the text is read; the first run after boot can take
    ~15–30 s while macOS loads that model.
  - Your model only ever receives text. If local recognition errors out, the
    image is sent to your model instead, which then does need image input.

Results appear in a floating panel. Every section runs at once and shows as soon
as it arrives, each with its own **Copy** and **Paste** buttons.

| Key | Selection Assistant / Friendly Reply | OCR Translate |
|---|---|---|
| `↩` | Read the selection again and rerun | Paste the first section |
| `⌘↩` | Paste the first section (Polish, or Translate & Learn) | Paste the first section |
| `⌘1`–`⌘9` | Paste that section | Paste that section |
| `esc` | Close | Close |

Paste goes straight back into the app you were in and leaves the text on the
clipboard. Pressing a command's shortcut again always reads the selection
afresh, so what's on screen is never a stale result.

## How the selection is read

PromptBar first asks the frontmost app for its selection through the
Accessibility API, which leaves the clipboard alone. Apps that don't expose it
that way (many Electron apps and web views) get a simulated `⌘C` instead, and
the clipboard's previous contents are put back right after.

## Setup

1. Build and install (below), then open PromptBar. Settings opens on first run.
2. **Model** tab:
   - **API Key** — your provider's key. Stored in the login keychain.
   - **Base URL** — an OpenAI-compatible base URL (defaults to OpenRouter).
   - **Model** — the exact model ID from your provider.
3. **Shortcuts** tab: record a shortcut for each command.
4. **General** tab: grant **Accessibility** (reading the selection, pasting)
   and **Screen Recording** (OCR Translate), and optionally open at login.

Any OpenAI-compatible endpoint works: OpenRouter, OpenAI directly, or a
self-hosted gateway. Plain HTTP is accepted only for a model on `localhost`.

### Moving over from the Raycast extension

Raycast keeps extension preferences encrypted, so copy them by hand: open
Raycast → Settings → Extensions → Prompt, and carry **API Key**, **Base URL** and
**Model** into the Model tab, and the Selection Assistant / Friendly Reply / OCR
Translate hotkeys into the Shortcuts tab. Remove the hotkeys from Raycast first
(or disable the extension): while Raycast holds a shortcut, PromptBar can't
register it and says so under the recorder.

The prompts are the extension's, word for word.

## Build

Requires macOS 14+ and Xcode (Swift 6 toolchain). Liquid Glass needs macOS 26;
older systems get a material fallback.

```sh
swift test               # prompts, request building, errors, Markdown parsing
./Scripts/bundle.sh      # → build/PromptBar.app, installed in /Applications
```

`bundle.sh` wraps the binary in an `.app` and signs it with your Developer ID or
Apple Development certificate (falling back to ad-hoc; set `CODESIGN_IDENTITY`
to choose one). A stable signature matters here: macOS ties the Accessibility
and Screen Recording grants and the keychain item to it, and an ad-hoc build
loses them on every rebuild. It then installs over `/Applications/PromptBar.app`,
quitting and relaunching a running copy. Pass `--no-install` to stop at
`build/`.

The icon is drawn by `swift Scripts/make-icon.swift`.

## License

[GPL-3.0-or-later](LICENSE).
