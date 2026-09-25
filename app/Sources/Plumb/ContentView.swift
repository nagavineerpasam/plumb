import SwiftUI
import WritingSignalsCore

struct ContentView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false
    @State private var confirmDelete: Note?
    @State private var renaming: Note?

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { model.selection }, set: { model.open($0) })) {
                ForEach(model.store?.notes ?? []) { note in
                    NoteRow(note: note, status: model.status(of: note), isSelected: note == model.selection,
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Button { showSettings.toggle() } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $showSettings, arrowEdge: .top) { SettingsView() }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .overlay(alignment: .top) { Divider() }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
            .toolbar {
                Button { model.newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
                    .keyboardShortcut("n")
            }
        } detail: {
            // "Soft": the page on a white rounded sheet, the signals as tiles beside it.
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    if model.selection == nil {
                        ContentUnavailableView {
                            Label("No note open", systemImage: "note.text")
                        } actions: {
                            Button("New Note") { model.newNote() }.buttonStyle(.borderedProminent)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.selection?.title ?? "")
                            .font(.system(size: 26, weight: .semibold))
                            .padding(.horizontal, 52).padding(.top, 40)
                        SignalEditor(analyzer: model.analyzer, noteID: model.selection?.url,
                                     initialText: model.openedText, onChange: model.edited)
                    }
                    .opacity(model.selection == nil ? 0 : 1)
                }
                .frame(maxWidth: 820, maxHeight: .infinity)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                .frame(maxWidth: .infinity)

                if model.showDashboard {
                    Dashboard(summary: model.analyzer.summary,
                              pending: model.analyzer.sentences.filter { $0.signals == nil }.count)
                        .frame(width: 280)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
            .background(Palette.canvas)
            .navigationTitle(model.selection?.title ?? "Plumb")
            .navigationSubtitle(model.statusLine)
            .toolbar {
                Button { withAnimation(.smooth) { model.showDashboard.toggle() } } label: {
                    Label("Signals", systemImage: "sidebar.right")
                }
                .help("Show or hide signals")
            }
            .onChange(of: model.analyzer.summary) { _, summary in model.record(summary) }
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
    let status: NoteStatus
    let isSelected: Bool
    @Binding var isRenaming: Bool
    let open: () -> Void
    let rename: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(status.color).frame(width: 8, height: 8)
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

/// How a note looked the last time it was checked in this session.
enum NoteStatus {
    case unchecked, clean, mechanics, attention

    var color: Color {
        switch self {
        case .unchecked: Color.secondary.opacity(0.35)
        case .clean: .green
        case .mechanics: .orange
        case .attention: .red
        }
    }
}
