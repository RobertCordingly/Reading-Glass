# Fix "Cannot find type in scope" in Xcode

The new Swift files (Models, SectionParser, SearchResultsView, etc.) need to be in the **SpeakEasy** target. Add them like this:

## Option A: Add files in Xcode (recommended)

1. **Close Xcode** completely (⌘Q).
2. **Reopen** the project: open `SpeakEasy.xcodeproj`.
3. In the Project Navigator (left sidebar), right‑click the **SpeakEasy** group.
4. Choose **"Add Files to 'SpeakEasy'..."**.
5. Go to the `SpeakEasy` folder (the one that contains `ContentView.swift`).
6. Select these files (⇧-click to select multiple):
   - `Models.swift`
   - `SectionParser.swift`
   - `SearchResultsView.swift`
   - `CleanupLogView.swift`
   - `OptionsView.swift`
   - `PronunciationEditorView.swift`
   - `SummarySheetView.swift`
   - `PDFComponents.swift`
7. **Leave unchecked**: "Copy items if needed".
8. **Ensure checked**: "Add to targets: SpeakEasy".
9. Click **Add**.
10. If Xcode says a file is already added, choose **"Replace"** or skip that file.
11. **Product → Clean Build Folder** (⇧⌘K).
12. **Product → Build** (⌘B).

## Option B: Check target membership

If the files already appear in the Project Navigator:

1. Select each file: `Models.swift`, `SectionParser.swift`, etc.
2. Open the **File Inspector** (right sidebar, first tab).
3. Under **Target Membership**, ensure **SpeakEasy** is checked.

## Option C: Reset build system

1. **Product → Clean Build Folder** (⇧⌘K).
2. Quit Xcode.
3. In Terminal, run:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData/SpeakEasy-*
   ```
4. Reopen the project and build.
