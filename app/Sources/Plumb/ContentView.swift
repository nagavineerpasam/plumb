import SwiftUI
import WritingSignalsCore

/// "Soft": one calm canvas with three columns (notes, the page on a white sheet, signal tiles)
/// and no title bar, only the window buttons floating top left.
struct ContentView: View {
    @Bindable var model: AppModel
    @State private var showSettings = false
    @State private var confirmDelete: Note?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            sidebar.frame(width: 220)
            page
            if model.showDashboard && !model.showingProgress {
                Dashboard(summary: model.analyzer.summary,
                          pending: model.analyzer.sentences.filter { $0.signals == nil }.count,
                          hasText: !model.analyzer.sentences.isEmpty,
                          noteID: model.selection?.url,
                          checkFlow: model.analyzer.checkFlow)
                    .frame(width: 320)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12).padding(.bottom, 12)
        .padding(.top, 44)  // room for the window buttons
        .background(alignment: .top) { TitleBarArea().frame(height: 44) }
        .background(Palette.canvas)
        .ignoresSafeArea()
        .onChange(of: model.analyzer.summary) { _, summary in model.record(summary) }
        .overlay {
            if case let .downloading(done, total, problem) = model.phase {
                Onboarding(step: model.setupStep, downloaded: done, total: total, problem: problem).transition(.opacity)
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
            sidebarButton("New chat", systemImage: "plus") { model.newNote() }
                .padding(.bottom, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.store?.notes ?? []) { note in
                        NoteRow(note: note, status: model.status(of: note), isSelected: note == model.selection,
                                open: { model.open(note) })
                            .contextMenu {
                                Button("Delete…", role: .destructive) { confirmDelete = note }
                            }
                    }
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 8)
            sidebarButton("Progress", systemImage: "chart.line.uptrend.xyaxis") {
                withAnimation(.smooth) { model.showingProgress.toggle() }
            }
            sidebarButton("Settings", systemImage: "gearshape") { showSettings.toggle() }
                .popover(isPresented: $showSettings, arrowEdge: .trailing) { SettingsView() }
        }
    }

    @ViewBuilder
    private var page: some View {
        if model.showingProgress {
            ProgressPage(progress: model.progress, version: model.progressVersion,
                         notes: model.store?.notes ?? [], open: { model.open($0) })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
                .transition(.opacity)
        } else {
            notePage
        }
    }

    private var notePage: some View {
        ZStack {
            if model.selection == nil {
                ContentUnavailableView {
                    Label("No chat open", systemImage: "bubble.left.and.text.bubble.right")
                } actions: {
                    Button("New chat") { model.newNote() }.buttonStyle(.borderedProminent)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                if model.dictation.settingUpFirstTime, let progress = model.dictation.preparing {
                    VoiceSetupBar(progress: progress)
                        .padding(.horizontal, 20).padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                HStack {
                    TitleField(title: model.selection?.title ?? "") { model.renameSelection(to: $0) }
                    Spacer()
                    MicButton(dictation: model.dictation)
                    Button { withAnimation(.smooth) { model.showDashboard.toggle() } } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(.borderless).foregroundStyle(.tertiary)
                    .pointingHand()
                    .help(model.showDashboard ? "Hide signals" : "Show signals")
                }
                .padding(.horizontal, 52).padding(.top, model.dictation.settingUpFirstTime ? 20 : 40)
                SignalEditor(analyzer: model.analyzer, dictation: model.dictation, noteID: model.selection?.url,
                             initialText: model.openedText, onChange: model.edited)
            }
            .opacity(model.selection == nil ? 0 : 1)
            .animation(.smooth, value: model.dictation.settingUpFirstTime)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            GeometryReader { geo in
                if model.dictation.isListening && !model.dictation.heardSomething {
                    VStack(spacing: 14) {
                        Image(systemName: "waveform")
                            .font(.system(size: 34, weight: .medium))
                            .symbolEffect(.variableColor.iterative, isActive: true)
                        Text("Listening").font(.system(size: 28, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .animation(.smooth, value: model.dictation.heardSomething)
        }
        .overlay(alignment: .bottom) {
            if let nudge = model.nudge, !model.dictation.isListening {
                ScoreNudgeBar(message: nudge, newChat: { model.newNote() }, close: { model.closeNudge() })
                    .padding(.horizontal, 28).padding(.bottom, 22)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: model.nudge)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
    }

    private func sidebarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.medium)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Palette.card.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)  // typing must never "press" a sidebar button
        .pointingHand()
    }
}

/// A chat in the sidebar: status dot, title, when it was last changed. The open one sits on a
/// white pill. A click just opens it; renaming happens in the chat's own title.
struct NoteRow: View {
    let note: Note
    let status: NoteStatus
    let isSelected: Bool
    let open: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(status.color).frame(width: 8, height: 8)
            Text(note.title).lineLimit(1)
            Spacer()
            Text(note.modified, format: .relative(presentation: .named, unitsStyle: .narrow))
                .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
        }
        .font(.system(size: 14, weight: isSelected ? .medium : .regular))
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.card)
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
            }
        }
        .contentShape(Rectangle())
        .pointingHand()
        .onTapGesture(perform: open)
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

/// The page heading. Click it to rename the note in place; Return or clicking away saves,
/// Esc cancels. The sidebar shows the new name straight away.
struct TitleField: View {
    let title: String
    let rename: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Untitled", text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 24, weight: .semibold))
            .focused($focused)
            .onSubmit { focused = false }
            .onExitCommand { draft = title; focused = false }
            .onChange(of: focused) { _, now in if !now { commit() } }
            .onChange(of: title, initial: true) { _, new in draft = new }
    }

    private func commit() {
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty || clean == title { draft = title } else { rename(clean) }
    }
}

/// A small rounded "Speak" pill by the title. Click (or ⌥⌘D) to speak into the note at the
/// cursor; click again to stop. While listening it turns accent-coloured and glows with the level.
/// The first time, it shows the voice model downloading and getting ready.
struct MicButton: View {
    @Bindable var dictation: Dictation

    private var title: String {
        if dictation.preparing != nil { return "Starting…" }
        return dictation.isListening ? "Listening" : "Speak"
    }

    var body: some View {
        Button { dictation.toggle() } label: {
            HStack(spacing: 7) {
                if dictation.isListening {
                    Circle().fill(.white).frame(width: 7, height: 7)
                        .phaseAnimator([1.0, 0.35]) { dot, opacity in dot.opacity(opacity) } animation: { _ in .easeInOut(duration: 0.8) }
                } else {
                    Image(systemName: "mic")
                }
                Text(title)
            }
                .font(.callout.weight(.medium))
                .foregroundStyle(dictation.isListening ? Color.white : Color.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background {
                    Capsule().fill(dictation.isListening ? Color.accentColor : Color.secondary.opacity(0.12))
                        .shadow(color: .accentColor.opacity(dictation.isListening ? 0.25 + dictation.level * 0.6 : 0),
                                radius: 4 + dictation.level * 10)
                }
                .animation(.easeOut(duration: 0.12), value: dictation.level)
        }
        .buttonStyle(.plain)
        .disabled(dictation.preparing != nil)
        .pointingHand()
        .keyboardShortcut("d", modifiers: [.option, .command])
        .help(dictation.isListening ? "Click to stop (⌥⌘D)" : "Speak into your note (⌥⌘D)")
        .alert(dictation.problem ?? "", isPresented: Binding(get: { dictation.problem != nil },
                                                             set: { if !$0 { dictation.problem = nil } })) {}
    }
}

/// The strip along the top where a title bar would be: drag to move the window, double-click to
/// zoom or minimise, following System Settings → Desktop & Dock → "Double-click a window's title bar".
struct TitleBarArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitleBarView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class TitleBarView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.performMiniaturize(nil)
                case "None": break
                default: window.performZoom(nil)
                }
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

extension View {
    /// Shows the pointing-hand cursor over something clickable, like a link.
    func pointingHand() -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active: NSCursor.pointingHand.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}

/// Shown across the top of the note the very first time Speak is used, while the voice model
/// downloads and is prepared for this Mac. It never appears again.
struct VoiceSetupBar: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(progress < 1 ? "Setting up voice for the first time. This happens only once."
                                   : "Almost ready… preparing voice for this Mac.",
                      systemImage: "waveform")
                    .font(.callout.weight(.medium))
                Spacer()
                if progress < 1 {
                    Text("\(Int(progress * 100))%").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if progress < 1 {
                ProgressView(value: progress).progressViewStyle(.linear)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// A rounded bar floating at the bottom of a scored chat, in the website's warm sunrise colours:
/// how you did compared with last time, and a cute button to go again.
struct ScoreNudgeBar: View {
    let message: String
    let newChat: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.sunrise)
            Text(message)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 8)
            Button(action: newChat) {
                Label("New chat", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Palette.sunrise, in: Capsule())
                    .shadow(color: Palette.sunrise.opacity(0.35), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .pointingHand()
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .pointingHand()
            .help("Hide for this chat")
        }
        .padding(.leading, 18).padding(.trailing, 10).padding(.vertical, 10)
        .background(Palette.sunriseWash, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.sunrise.opacity(0.28)))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
    }
}
