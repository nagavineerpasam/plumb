import SwiftUI
import WritingSignalsCore

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var confirmDelete: Note?
    @State private var renaming: Note?
    @State private var newTitle = ""

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.selection }, set: { model.open($0) })) {
                ForEach(model.store?.notes ?? []) { note in
                    HStack {
                        Text(note.title).lineLimit(1)
                        Spacer()
                        Text(note.modified, format: .relative(presentation: .named, unitsStyle: .narrow))
                            .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                    }
                    .tag(note)
                        .contextMenu {
                            Button("Rename…") { newTitle = note.title; renaming = note }
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
                        Button { model.showDashboard.toggle() } label: { Label("Signals", systemImage: "chart.bar.xaxis") }
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
        .alert("Rename note", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") { renaming.map { model.rename($0, to: newTitle) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}
