# Reading Glass

**A native macOS, iPadOS, and Android app that reads academic PDFs aloud — and (on Apple platforms) uses a local LLM to make them actually pleasant to listen to.**

Reading Glass loads a PDF, extracts and tidies up the prose, and plays it back through a system text‑to‑speech voice while highlighting the current word in both the reader pane and the PDF itself. On macOS/iPadOS, optional AI cleanup runs through a **local language model** (LM Studio by default, Apple Intelligence as a fallback) to strip out figures, tables, captions, page headers, and OCR garbage that would otherwise turn a paper into an unlistenable slog.

The app is intentionally local‑first. Your PDFs and your text never leave your device.

> The Android version ships the same PDF reader, TTS playback, text cleanup, pronunciations, sections, and search as the Apple build. The **AI Cleanup / Summary** features are macOS/iPadOS only.

---

## Features

### Reading
- **Native PDF viewer** with a thumbnail strip, zoom controls, and click‑to‑jump word selection.
- **Word‑level highlighting** in the PDF that follows the speech cursor in real time.
- **Reader pane** with a synchronized cursor, click‑to‑seek, and a clean reading layout.
- **Section parsing** of common academic headings (Abstract, Introduction, Methods, Results, References, …) for fast navigation.
- **Search** with snippet previews across the cleaned text.

### Speech
- Built on `AVSpeechSynthesizer` — works fully offline on every Mac and iPad.
- Voice picker covering all installed English voices (defaults to *Samantha (Enhanced)* if available).
- Variable playback speed (0.5× – 4×).
- Sentence skip forward / backward.
- Floating glass playback pill with section context.

### Text Processing
Before anything is read, the raw extracted text is normalized:
- PDF ligatures (`ﬁ`, `ﬂ`, `ﬃ`, …) are decomposed.
- Smart quotes, em/en dashes, ellipses, and exotic spaces are normalized.
- Optional removal of inline citations (`[1]`, `[2–5]`).
- Optional reading of Greek letters (α → "alpha") and math symbols (≤ → "less than or equal to").
- Optional truncation of everything before *Abstract* and after *References*.
- A fully editable **pronunciation table** (find/replace) for terms like `vCPU` → "virtual CPU".

### AI Cleanup & Summarization (Local LLMs)
Reading Glass supports two **local** LLM backends, selected in *Options → AI Provider*:

| Backend | What it is | Best for |
| --- | --- | --- |
| **LM Studio** *(recommended)* | An OpenAI‑compatible HTTP server you run locally. Pick whatever model you have hardware for (Llama, Qwen, Mistral, Gemma, …). | Quality and flexibility — you control the model. |
| **Apple Intelligence** | The on‑device system language model (`FoundationModels`). | Zero setup on supported Macs / iPads. |

Both backends drive two AI features:

1. **Chunk‑based AI Cleanup.** Sentences are grouped into chunks around the current cursor and run through a two‑pass pipeline (typo fix → content cleanup) using a prompt you can edit. The result is merged back in with a full diff log and per‑chunk revert.
2. **Section Summary.** A button in the toolbar summarizes whatever section the cursor is currently sitting in.

All AI traffic stays on your machine — there is no cloud component anywhere in the app.

---

## Setting up LM Studio

If you want better quality than Apple Intelligence (which is the whole reason the LM Studio backend exists), point Reading Glass at LM Studio:

1. Install [LM Studio](https://lmstudio.ai/) and download a chat‑tuned model. An 8B–14B instruct model is a good starting point on Apple Silicon. Larger if you have the RAM, smaller if you don't.
2. In LM Studio, open the **Developer** tab and **Start Server**. Confirm it's listening on `http://localhost:1234` (the default).
3. In Reading Glass, open **Options** (⚙️ in the toolbar), select **LM Studio (Local Endpoint)** under *AI Provider*, and:
   - Leave *Server URL* as `http://localhost:1234/v1` unless you changed the port.
   - Click **Refresh** next to *Model* to pick from currently loaded models, or leave it blank to use whatever LM Studio has loaded.
   - *API Key* can stay empty unless you've enabled auth in LM Studio.
   - Click **Test Connection** — you should see a green checkmark.
4. Open a PDF, scroll to the section you want to read, and either:
   - Click **AI Cleanup** in the toolbar to clean ±5 chunks around the cursor, or
   - Click **AI Summary** to summarize the current section.

### Tuning tips
- **Temperature** is exposed in *Options* — keep it low (0.1–0.3) for cleanup so the model doesn't paraphrase. Bump it slightly higher for summaries if you want.
- The cleanup prompt is fully editable in *Options → AI Cleanup → Prompt*. Edit it to match the kind of documents you read.
- Cleanup walks ±5 chunks around the cursor, so move through the paper as you listen and let cleanup follow.

---

## Apple Intelligence backend

If your Mac or iPad supports Apple Intelligence and you'd rather not run a separate server, switch *AI Provider* to **Apple Intelligence**. There's no extra setup, but quality is bound by the on‑device system model — which is why the LM Studio path exists.

---

## Building from source

### macOS / iPadOS

**Requirements**
- Xcode 16 or newer
- macOS 26 or iPadOS 26 (the `FoundationModels` framework requires the modern SDK; it's only loaded when the Apple Intelligence backend is selected)
- LM Studio installed locally if you want to use that backend

**Clone & open**
```bash
git clone https://github.com/RobertCordingly/Reading-Glass.git
cd Reading-Glass
open SpeakEasy.xcodeproj
```

Build and run the **SpeakEasy** scheme on either *My Mac* or an iPad simulator/device.

> The internal target is named `SpeakEasy`; the user‑facing display name is **Reading Glass** (configured via `INFOPLIST_KEY_CFBundleDisplayName`).

The project is currently configured **without** the App Sandbox (`CODE_SIGN_ENTITLEMENTS = ""`), so connecting to `http://localhost:1234` works out of the box. If you later enable sandboxing, add `com.apple.security.network.client` to your entitlements so the LM Studio backend can reach the local server.

### Android

**Requirements**
- Android Studio Koala (2024.1) or newer, or a standalone JDK 17 + Android command-line tools
- Android SDK with platform 34, build-tools 34.0.0+
- A device or emulator running Android 7.0 (API 24) or newer

**Build**
```bash
cd android
# First-time only — generate the Gradle wrapper.
gradle wrapper
./gradlew :app:installDebug
```

Or open `android/` as a project in Android Studio and run the **app** configuration.

**What's included**
- PDF rendering via Android's built-in `PdfRenderer`
- Text extraction via [PDFBox-Android](https://github.com/TomRoush/PdfBox-Android)
- TTS via `android.speech.tts.TextToSpeech` (no extra setup; works offline with installed system voices)
- Section parsing, search, pronunciations, and the same `TextProcessor` pipeline as the Apple build (Greek letters, math symbols, ligatures, citations, etc.)

**What's *not* included on Android**
- AI Cleanup and AI Summary. The Android build is TTS-only. If you want LLM-driven cleanup, use the macOS / iPadOS build with LM Studio or Apple Intelligence.

---

## Project layout

```
SpeakEasy/                macOS / iPadOS app (Swift + SwiftUI)
├── App/                  SpeakEasyApp.swift — app entry point, commands
├── Views/                SwiftUI views (ContentView, OptionsView, …)
├── Models/               Lightweight value types
├── Components/           PDFKit wrappers, section parser, search field
├── Managers/
│   ├── SpeechManager.swift      AVSpeechSynthesizer driver, cursor tracking
│   └── AICleanupManager.swift   LLM backends + chunk pipeline + summary
├── Processing/           PDF import, text normalization
├── Resources/            Assets.xcassets
└── PlatformAdapters.swift  macOS / iOS color & clipboard shims

android/                  Android app (Kotlin + Jetpack Compose)
├── app/src/main/kotlin/com/readingglass/
│   ├── MainActivity.kt            Activity entry point
│   ├── ReadingGlassApplication.kt PDFBox bootstrap
│   ├── models/Models.kt           Value types (SectionItem, SearchResult, …)
│   ├── processing/
│   │   ├── TextProcessor.kt       Port of the Swift TextProcessor
│   │   ├── SectionParser.kt       Port of SectionParser
│   │   ├── PdfImporter.kt         PDFBox-Android text extraction
│   │   └── PdfRendering.kt        PdfRenderer-based page bitmaps
│   ├── managers/SpeechManager.kt  android.speech.tts driver, cursor tracking
│   ├── store/Preferences.kt       SharedPreferences-backed settings
│   └── ui/                        Compose screens (PdfViewer, ReaderText, …)
└── app/src/main/res/              Manifest, themes, icons
```

The AI provider layer (`LLMBackend`, `AppleIntelligenceBackend`, `LMStudioBackend`, `LLMSettings`) lives in `Managers/AICleanupManager.swift` and is the single entry point for adding more local backends in the future (e.g. Ollama, llama.cpp, MLX). The Android build intentionally omits this layer.

---

## Roadmap / ideas

- Streaming responses from LM Studio (tokens appear in the cleanup log as they arrive).
- Additional local backends: Ollama, MLX, llama.cpp server.
- Per‑section caching of cleaned chunks across sessions.
- A "explain this passage" button alongside summary.

PRs and issues welcome.

---

## License

See repository for license details.
