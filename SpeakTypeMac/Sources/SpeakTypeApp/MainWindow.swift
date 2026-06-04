import SwiftUI
import SpeakTypeCore

/// The scratchpad window (spec §2.3, layout B): a sidebar of saved notes on the left, a plain-text
/// editor for the selected note on the right. Reads/writes `NotesModel`; the same glass aesthetic
/// as the pill. Settings + delete arrive in UI-10.
struct MainWindow: View {
    static let id = "main"

    @ObservedObject var notes: NotesModel
    let settings: SettingsModel

    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            editor
                .id(notes.activeID)                       // new identity per note → cross-fade
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: notes.activeID)
        .frame(minWidth: 640, minHeight: 420)
        .sheet(isPresented: $showSettings) { SettingsView(model: settings) }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(notes.notes) { note in
                NoteRow(note: note)
                    .tag(note.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) { notes.delete(note.id) }
                    }
            }
        }
        // Animate inserts/deletes and the newest-first reorder — a dictated note gliding to the
        // top is the gentle "transcript landed" cue at the list level.
        .animation(.easeInOut(duration: 0.25), value: notes.notes.map(\.id))
        .overlay {
            if notes.notes.isEmpty {
                ContentUnavailableView {
                    Label("No notes yet", systemImage: "note.text")
                } description: {
                    Text("Dictate with Fn while this window is focused, or create a note to start.")
                } actions: {
                    Button("New note") { notes.newNote() }
                }
            }
        }
        .navigationTitle("Notes")
        .toolbar {
            Button { notes.newNote() } label: { Label("New note", systemImage: "square.and.pencil") }
            Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
        }
    }

    private var selection: Binding<Note.ID?> {
        Binding(get: { notes.activeID }, set: { if let id = $0 { notes.select(id) } })
    }

    // MARK: - Editor

    @ViewBuilder private var editor: some View {
        if let id = notes.activeID {
            TextEditor(text: body(of: id))
                .font(DS.Typography.body)
                .scrollContentBackground(.hidden)
                .background(.ultraThinMaterial)
                .padding(DS.Space.lg)
        } else {
            ContentUnavailableView(
                "No note selected", systemImage: "note.text",
                description: Text("Create a note to start writing."))
        }
    }

    /// Two-way binding from the editor to the active note's body. Writes go through `NotesModel`,
    /// which bumps `updatedAt`, re-sorts, and (debounced) persists.
    private func body(of id: Note.ID) -> Binding<String> {
        Binding(
            get: { notes.notes.first { $0.id == id }?.body ?? "" },
            set: { notes.setBody($0, for: id) })
    }
}

/// One row in the sidebar: title (first non-empty line, or "New note"), a preview line, and the
/// relative edit time.
private struct NoteRow: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(note.title.isEmpty ? "New note" : note.title)
                .font(DS.Typography.body)
                .lineLimit(1)
            HStack {
                Text(preview)
                    .lineLimit(1)
                Spacer()
                Text(note.updatedAt, format: .relative(presentation: .named))
            }
            .font(DS.Typography.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, DS.Space.xs)
    }

    /// The first body line after the title line, or a placeholder when the note is otherwise empty.
    private var preview: String {
        let lines = note.body.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.count > 1 ? String(lines[1]) : (note.title.isEmpty ? "No additional text" : " ")
    }
}
