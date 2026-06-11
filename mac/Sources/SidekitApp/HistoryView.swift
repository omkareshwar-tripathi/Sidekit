import SwiftUI
import AppKit
import SidekitCore

/// The dictation-trail sheet shown from the window's clock button: every logged dictation,
/// newest-first, each row showing relative time, where the text went, the text itself, and a Copy
/// button that puts it back on the clipboard. Matches `SettingsView`'s look and fixed frame.
struct HistoryView: View {
    @ObservedObject var history: HistoryModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if history.entries.isEmpty {
                    ContentUnavailableView(
                        "No dictations yet", systemImage: "clock.arrow.circlepath",
                        description: Text("Hold Fn to dictate — every transcript shows up here."))
                } else {
                    List(history.entries) { entry in
                        EntryRow(entry: entry)
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(width: 460, height: 420)
    }
}

/// One trail row: relative time + outcome label on top, the text below, a Copy button trailing.
private struct EntryRow: View {
    let entry: DictationHistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                HStack(spacing: DS.Space.sm) {
                    Text(entry.date, format: .relative(presentation: .named))
                    Text(outcomeLabel)
                        .foregroundStyle(.secondary)
                }
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)

                Text(entry.text)
                    .font(DS.Typography.body)
                    .lineLimit(4)
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Copy to clipboard")
        }
        .padding(.vertical, DS.Space.xs)
    }

    /// Human-readable destination for the dictation.
    private var outcomeLabel: String {
        switch entry.outcome {
        case .pasted: return "Pasted"
        case .leftOnClipboard: return "Copied to clipboard"
        case .addedToNote: return "Added to note"
        case .noSpeech: return "No speech" // never logged in practice, but total
        }
    }
}
