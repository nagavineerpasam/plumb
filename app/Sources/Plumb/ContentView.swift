import SwiftUI
import WritingSignalsCore

/// "Soft": one calm canvas with three columns (notes, the page on a white sheet, signal tiles)
/// and no title bar, only the window buttons floating top left.
struct ContentView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false
    @State private var confirmDelete: Note?
    @State private var renaming: Note?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            sidebar.frame(width: 220)
            page
            if model.showDashboard {
                Dashboard(summary: model.analyzer.summary,
                          pending: model.analyzer.sentences.filter { $0.signals == nil }.count)
                    .frame(width: 280)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
        .padding(.top, 44)  // room for the window buttons
        .background(Palette.canvas)
        .ignoresSafeArea()
        .onChange(of: model.analyzer.summary) { _, summary in model.record(summary) }
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

    // MARK: Columns

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.store?.notes ?? []) { note in
                        NoteRow(note: note, status: model.status(of: note), isSelected: note == model.selection,
                                isRenaming: Binding(get: { renaming == note }, set: { renaming = $0 ? note : nil }),
                                open: { model.open(note) },
                                rename: { model.rename(note, to: $0) })
                            .contextMenu {
                                Button("Rename") { renaming = note }
                                Button("Delete…", role: .destructive) { confirmDelete = note }
                            }
                    }
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 8)
            sidebarButton("New note", systemImage: "plus") { model.newNote() }
                .keyboardShortcut("n")
            sidebarButton("Settings", systemImage: "gearshape") { showSettings.toggle() }
                .popover(isPresented: $showSettings, arrowEdge: .trailing) { SettingsView() }
        }
    }

    private var page: some View {
        ZStack {
            if model.selection == nil {
                ContentUnavailableView {
                    Label("No note open", systemImage: "note.text")
                } actions: {
                    Button("New note") { model.newNote() }.buttonStyle(.borderedProminent)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.selection?.title ?? "")
                        .font(.system(size: 24, weight: .semibold))
                    Spacer()
                    Button { withAnimation(.smooth) { model.showDashboard.toggle() } } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(.borderless).foregroundStyle(.tertiary)
                    .help(model.showDashboard ? "Hide signals" : "Show signals")
                }
                .padding(.horizontal, 52).padding(.top, 40)
                SignalEditor(analyzer: model.analyzer, noteID: model.selection?.url,
                             initialText: model.openedText, onChange: model.edited)
            }
            .opacity(model.selection == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }

    private func sidebarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A note in the sidebar: status dot, title, when it was last changed. The open note sits on a
/// white pill. Click the open note's title (or double-click any note) to rename it in place.
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
            }
            Spacer()
            Text(note.modified, format: .relative(presentation: .named, unitsStyle: .narrow))
                .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
        }
        .font(.system(size: 14, weight: isSelected ? .medium : .regular))
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.card)
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open(); isRenaming = true }
        .onTapGesture { isSelected ? (isRenaming = true) : open() }
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
