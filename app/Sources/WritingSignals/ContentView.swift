import SwiftUI
import WritingSignalsCore

struct ContentView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = Appearance.system
    @State private var confirmDelete: Note?
    @State private var renaming: Note?

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.selection }, set: { model.open($0) })) {
                ForEach(model.store?.notes ?? []) { note in
                    NoteRow(note: note, isSelected: note == model.selection,
                            isRenaming: Binding(get: { renaming == note }, set: { renaming = $0 ? note : nil }),
                            open: { model.open(note) },
                            rename: { model.rename(note, to: $0) })
                        .tag(note)
                        .contextMenu {
                            Button("Rename") { renaming = note }
                            Button("Delete…", role: .destructive) { confirmDelete = note }
                        }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .toolbar {
                Button { model.newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
                    .keyboardShortcut("n")
            }
        } detail: {
            ZStack {
                if model.selection == nil {
                    ContentUnavailableView {
                        Label("No note open", systemImage: "note.text")
                    } actions: {
                        Button("New Note") { model.newNote() }.buttonStyle(.borderedProminent)
                    }
                }
                SignalEditor(analyzer: model.analyzer, noteID: model.selection?.url,
                             initialText: model.openedText, onChange: model.edited)
                    .opacity(model.selection == nil ? 0 : 1)
            }
            .navigationTitle(model.selection?.title ?? "Writing Signals")
            .navigationSubtitle(model.statusLine)
            .inspector(isPresented: $model.showDashboard) {
                Dashboard(summary: model.analyzer.summary,
                          pending: model.analyzer.sentences.filter { $0.signals == nil }.count)
                    .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
                    .toolbar {
                        Menu {
                            Picker("Appearance", selection: $appearance) {
                                ForEach(Appearance.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.inline)
                        } label: {
                            Label("Appearance", systemImage: "circle.lefthalf.filled")
                        }
                        .help("Light, dark or match the system")
                        .onChange(of: appearance) { _, value in value.apply() }
                        Button { model.showDashboard.toggle() } label: { Label("Signals", systemImage: "chart.bar.xaxis") }
                            .help("Show or hide signals")
                    }
            }
        }
        .overlay {
            if case let .downloading(done, total, problem) = model.phase {
                Onboarding(downloaded: done, total: total, problem: problem).transition(.opacity)
            }
        }
        .alert(model.error ?? "", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {}
        .confirmationDialog("Move “\(confirmDelete?.title ?? "")” to the Trash?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Move to Trash", role: .destructive) { confirmDelete.map(model.delete) }
        }
    }
}

/// A note in the sidebar. Click the selected note's title (or double-click any note) to rename it
/// in place; Return saves, Esc cancels.
struct NoteRow: View {
    let note: Note
    let isSelected: Bool
    @Binding var isRenaming: Bool
    let open: () -> Void
    let rename: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack {
            if isRenaming {
                TextField("Title", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(commit)
                    .onExitCommand { isRenaming = false }
                    .onChange(of: focused) { _, now in if !now { commit() } }
                    .onAppear { draft = note.title; focused = true }
            } else {
                Text(note.title).lineLimit(1)
                    .onTapGesture(count: 2) { open(); isRenaming = true }
                    .onTapGesture { isSelected ? (isRenaming = true) : open() }
            }
            Spacer()
            Text(note.modified, format: .relative(presentation: .named, unitsStyle: .narrow))
                .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
        }
        .contentShape(Rectangle())
    }

    private func commit() {
        guard isRenaming else { return }
        isRenaming = false
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, title != note.title { rename(title) }
    }
}
