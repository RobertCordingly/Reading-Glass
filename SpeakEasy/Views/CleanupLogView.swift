import SwiftUI

/// AI Cleanup log sheet with before/after diff view and revert support.
struct CleanupLogView: View {
    let cleanupLog: [CleanupLogEntry]
    let isCleaningInBackground: Bool
    let backgroundCleanProgress: Double
    let backgroundCleanStatus: String
    let onStopCleanup: () -> Void
    let onRevert: (CleanupLogEntry) -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "sparkles")
                Text("AI Cleanup Log")
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)

            if isCleaningInBackground {
                HStack(spacing: 8) {
                    ProgressView(value: backgroundCleanProgress)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                        .padding(.horizontal, 12)
                    Text(backgroundCleanStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(action: onStopCleanup) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Stop AI cleanup")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }

            Divider()

            if cleanupLog.isEmpty && !isCleaningInBackground {
                Text("No cleanup has run yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if cleanupLog.isEmpty {
                Text("Cleaning chunks...")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(cleanupLog) { entry in
                            CleanupLogEntryRow(entry: entry) {
                                onRevert(entry)
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: .infinity)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Diff helpers

private func diffSegments(before: String, after: String) -> (before: [(String, Bool)], after: [(String, Bool)]) {
    let b = Array(before)
    let a = Array(after)
    let n = b.count
    let m = a.count

    if n == 0 && m == 0 { return ([], []) }
    if n == 0 { return ([], [(after, true)]) }
    if m == 0 { return ([(before, true)], []) }

    var dp = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
    for i in 1...n {
        for j in 1...m {
            if b[i - 1] == a[j - 1] {
                dp[i][j] = dp[i - 1][j - 1] + 1
            } else {
                dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
            }
        }
    }

    var beforeSegments: [(String, Bool)] = []
    var afterSegments: [(String, Bool)] = []
    var i = n
    var j = m

    while i > 0 || j > 0 {
        if i > 0 && j > 0 && b[i - 1] == a[j - 1] {
            beforeSegments.append((String(b[i - 1]), false))
            afterSegments.append((String(a[j - 1]), false))
            i -= 1
            j -= 1
        } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
            afterSegments.append((String(a[j - 1]), true))
            j -= 1
        } else {
            beforeSegments.append((String(b[i - 1]), true))
            i -= 1
        }
    }

    func merge(_ segs: [(String, Bool)]) -> [(String, Bool)] {
        let reversed = segs.reversed()
        var result: [(String, Bool)] = []
        for (s, bold) in reversed {
            if let last = result.last, last.1 == bold {
                result[result.count - 1] = (last.0 + s, bold)
            } else {
                result.append((s, bold))
            }
        }
        return result
    }

    return (merge(beforeSegments), merge(afterSegments))
}

private func diffRenderedText(segments: [(String, Bool)], fontSize: CGFloat) -> Text {
    segments.reduce(Text("")) { acc, seg in
        acc + (seg.1 ? Text(seg.0).fontWeight(.bold) : Text(seg.0))
    }
    .font(.system(size: fontSize))
}

private struct CleanupLogDiffContent: View {
    let entry: CleanupLogEntry

    var body: some View {
        let (beforeSegs, afterSegs) = diffSegments(before: entry.beforeText, after: entry.afterText)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Before")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    diffRenderedText(segments: beforeSegs, fontSize: 11)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: 180)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 4) {
                Text("After")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                ScrollView {
                    diffRenderedText(segments: afterSegs, fontSize: 11)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: 180)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 6)
    }
}

private struct CleanupLogEntryRow: View {
    let entry: CleanupLogEntry
    let onRevert: () -> Void

    var body: some View {
        DisclosureGroup {
            CleanupLogDiffContent(entry: entry)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.sectionTitle)
                        .font(.system(size: 12, weight: .medium))
                    Text("\(entry.charsRemoved) chars removed (\(entry.originalLength) → \(entry.cleanedLength))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Revert") {
                    onRevert()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }
}
