import SwiftUI
import PDFKit

/// Floating liquid glass playback pill overlay — Apple Music style layout.
/// Displays transport controls, section jump, progress bar, speed, and voice.
struct PlaybackPillView: View {
    @ObservedObject var speechManager: SpeechManager
    let displayText: String
    let parsedSections: [SectionItem]
    let displaySectionOffsets: [Int]
    @Binding var speedMultiplier: Double
    var pdfViewInstance: PDFView?
    let jumpToSection: (SectionItem) -> Void

    @State private var showSpeedPopover = false
    @State private var showSectionJumpPopover = false

    private var playbackProgress: Double {
        let totalUTF16 = displayText.utf16.count
        guard totalUTF16 > 0 else { return 0 }
        return min(Double(speechManager.cursorUTF16) / Double(totalUTF16), 1.0)
    }

    private var estimatedTimeRemaining: String {
        let totalUTF16 = displayText.utf16.count
        guard totalUTF16 > 0 else { return "--:--" }

        let remainingUTF16 = max(totalUTF16 - speechManager.cursorUTF16, 0)
        let fractionRemaining = Double(remainingUTF16) / Double(totalUTF16)

        let totalWords = Double(totalUTF16) / 5.0
        let remainingWords = totalWords * fractionRemaining

        let wordsPerMinute = 180.0 * Double(speedMultiplier)
        let minutesLeft = remainingWords / wordsPerMinute

        let totalSeconds = Int(minutesLeft * 60)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private var currentSectionName: String {
        guard !parsedSections.isEmpty, !displaySectionOffsets.isEmpty else { return "" }
        let cursor = speechManager.cursorUTF16
        let idx = (0..<parsedSections.count).last(where: { displaySectionOffsets[$0] <= cursor }) ?? 0
        return parsedSections[idx].title
    }

    private var speedPresets: [(speed: Double, icon: String, wpm: Int)] {
        [
            (0.5, "tortoise.fill", estimatedWPM(for: 0.5)),
            (1.0, "figure.walk", estimatedWPM(for: 1.0)),
            (2.0, "hare.fill", estimatedWPM(for: 2.0)),
            (3.0, "car.fill", estimatedWPM(for: 3.0)),
            (4.0, "airplane", estimatedWPM(for: 4.0)),
        ]
    }

    private func speedIcon(for speed: Double) -> String {
        if speed < 0.75 { return "tortoise.fill" }
        if speed < 1.5 { return "figure.walk" }
        if speed < 2.5 { return "hare.fill" }
        if speed < 3.5 { return "car.fill" }
        return "airplane"
    }

    private func estimatedWPM(for speed: Double) -> Int {
        Int(180.0 * speed)
    }

    var body: some View {
        HStack(spacing: 16) {
            // Left: transport controls
            HStack(spacing: 20) {
                Button(action: {
                    speechManager.skipBackward(in: displayText)
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .help("Previous sentence")

                if speechManager.isPlaying {
                    Button(action: {
                        speechManager.pause()
                    }) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 26))
                    }
                    .buttonStyle(.plain)
                    .help("Pause")
                } else {
                    Button(action: {
                        speechManager.play(text: displayText)
                    }) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 26))
                    }
                    .buttonStyle(.plain)
                    .help("Play from cursor")
                }

                Button(action: {
                    speechManager.skipForward(in: displayText)
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .help("Next sentence")
            }

            Divider()
                .frame(height: 24)

            // Center: section name + progress bar
            if !displayText.isEmpty {
                VStack(spacing: 5) {
                    if !currentSectionName.isEmpty {
                        Button(action: {
                            showSectionJumpPopover.toggle()
                        }) {
                            HStack(spacing: 4) {
                                Text(currentSectionName)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showSectionJumpPopover) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(parsedSections) { section in
                                        Button(action: {
                                            showSectionJumpPopover = false
                                            jumpToSection(section)
                                        }) {
                                            Text(section.title)
                                                .font(.system(size: 12))
                                                .padding(EdgeInsets(top: 4, leading: section.level > 0 ? 16 : 0, bottom: 4, trailing: 0))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(10)
                            }
                            .frame(width: 260, height: min(CGFloat(parsedSections.count) * 28 + 20, 300))
                        }
                    }

                    HStack(spacing: 6) {
                        Text(String(format: "%.0f%%", playbackProgress * 100))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .trailing)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.primary.opacity(0.15))
                                    .frame(height: 6)
                                Capsule()
                                    .fill(.primary.opacity(0.5))
                                    .frame(width: max(geo.size.width * playbackProgress, 0), height: 6)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                let fraction = max(0, min(location.x / geo.size.width, 1.0))
                                let totalUTF16 = displayText.utf16.count
                                let targetUTF16 = Int(fraction * Double(totalUTF16))

                                let idx = String.Index(utf16Offset: min(targetUTF16, totalUTF16), in: displayText)
                                var wordStart = idx
                                while wordStart > displayText.startIndex && !displayText[displayText.index(before: wordStart)].isWhitespace {
                                    wordStart = displayText.index(before: wordStart)
                                }

                                if let coordinator = pdfViewInstance?.pageOverlayViewProvider as? PDFKitView.Coordinator {
                                    coordinator.bypassStabilization = true
                                }

                                speechManager.cursorUTF16 = wordStart.utf16Offset(in: displayText)
                                speechManager.cursorLengthUTF16 = 0

                                if speechManager.isPlaying {
                                    speechManager.stop()
                                    speechManager.play(text: displayText)
                                }
                            }
                        }
                        .frame(width: 120, height: 6)

                        HStack(spacing: 2) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                            Text(estimatedTimeRemaining)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 220)
            }

            Divider()
                .frame(height: 24)

            // Right: speed + voice icons
            HStack(spacing: 16) {
                Button(action: {
                    showSpeedPopover.toggle()
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: speedIcon(for: speedMultiplier))
                            .font(.system(size: 18))
                        Text(String(format: "%.1fx", speedMultiplier))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                }
                .buttonStyle(.plain)
                .help("Playback speed")
                .popover(isPresented: $showSpeedPopover) {
                    VStack(spacing: 12) {
                        Text("Playback Speed")
                            .font(.system(size: 13, weight: .semibold))

                        Image(systemName: speedIcon(for: speedMultiplier))
                            .font(.system(size: 32))
                            .padding(.top, 4)

                        Text(String(format: "%.1fx", speedMultiplier))
                            .font(.system(size: 22, weight: .bold, design: .rounded))

                        Text(String(format: "~%d words/min", estimatedWPM(for: speedMultiplier)))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Image(systemName: "tortoise.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Slider(value: $speedMultiplier, in: 0.5...4.0, step: 0.1)
                                .frame(width: 160)
                                .onChange(of: speedMultiplier) { _, newValue in
                                    speechManager.setRate(Float(newValue), restartWith: displayText)
                                }
                            Image(systemName: "airplane")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        HStack(spacing: 12) {
                            ForEach(speedPresets, id: \.speed) { preset in
                                Button(action: {
                                    speedMultiplier = preset.speed
                                    speechManager.setRate(Float(preset.speed), restartWith: displayText)
                                }) {
                                    VStack(spacing: 3) {
                                        Image(systemName: preset.icon)
                                            .font(.system(size: 16))
                                        Text(String(format: "%.1fx", preset.speed))
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                        Text("\(preset.wpm)")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 44, height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.primary.opacity(abs(speedMultiplier - preset.speed) < 0.05 ? 0.1 : 0))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(16)
                }

                Menu {
                    ForEach(speechManager.availableVoices, id: \.identifier) { voice in
                        Button(action: {
                            speechManager.setVoice(voice.identifier, restartWith: displayText)
                        }) {
                            if speechManager.selectedVoiceID == voice.identifier {
                                Label(voice.name, systemImage: "checkmark")
                            } else {
                                Text(voice.name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "person.wave.2.fill")
                        .font(.system(size: 24))
                        .help("Voice")
                }
                .menuStyle(.borderlessButton)
            }
        }
        //.foregroundStyle(.primary)
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .glassEffect()
    }
}
