import AppKit
import Observation
import WritingSignalsCore

/// Keeps Plumb up to date: asks GitHub for the latest release when the app opens (unless turned
/// off in Settings), and on "Update now" downloads it, checks its fingerprint, swaps the new app
/// into place and reopens Plumb. Downloaded by the app itself, the new version isn't marked as
/// "from the internet", so macOS doesn't ask again. Notes and settings are untouched.
@MainActor @Observable
final class Updater {
    enum State: Equatable {
        case idle, checking, upToDate
        case available(ReleaseInfo)
        case downloading(ReleaseInfo, Double)
        case installing(ReleaseInfo)
        case failed(String)
    }

    private(set) var state = State.idle
    /// The card in the main window; hidden by "Later" until the next version.
    private(set) var showCard = false

    static let latestRelease = URL(string: "https://api.github.com/repos/nagavineerpasam/plumb/releases/latest")!
    static let downloads = "https://github.com/nagavineerpasam/plumb/releases/download"

    static var current: AppVersion? {
        AppVersion(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
    }
    /// Only a packaged Plumb.app can replace itself (not `swift run`).
    static var canUpdate: Bool { Bundle.main.bundlePath.hasSuffix(".app") }

    var checkAutomatically: Bool {
        get { UserDefaults.standard.object(forKey: "checkForUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "checkForUpdates") }
    }
    private var dismissedTag: String? {
        get { UserDefaults.standard.string(forKey: "dismissedUpdate") }
        set { UserDefaults.standard.set(newValue, forKey: "dismissedUpdate") }
    }

    func checkOnLaunch() {
        guard Self.canUpdate, checkAutomatically else { return }
        Task { await check(userAsked: false) }
    }

    /// Asks GitHub for the latest release. `userAsked` (Settings → Check for updates) always shows
    /// the card; the launch check respects "Later".
    /// True while an update is downloading or installing: nothing may start a second one.
    var isUpdating: Bool {
        switch state { case .downloading, .installing: true; default: false }
    }

    func check(userAsked: Bool) async {
        guard !isUpdating else { return }
        state = .checking
        var request = URLRequest(url: Self.latestRelease, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = ReleaseInfo.parse(data), let current = Self.current else {
            state = userAsked ? .failed("Couldn't reach GitHub to check for updates. Try again later.") : .idle
            return
        }
        if release.version > current {
            state = .available(release)
            showCard = userAsked || dismissedTag != release.tag
        } else {
            state = .upToDate
        }
    }

    func later() {
        if case .available(let release) = state { dismissedTag = release.tag }
        showCard = false
    }

    func update() {
        guard case .available(let release) = state else { return }
        showCard = true
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("plumb-update-\(UUID().uuidString)")
        state = .downloading(release, 0)  // set at once, so a second click can't start another update
        Task {
            do { try await install(release, in: work) } catch {
                try? FileManager.default.removeItem(at: work)  // don't leave the download behind
                state = .failed("The update didn't finish: \(error.localizedDescription) Your current Plumb is unchanged.")
            }
        }
    }

    private func install(_ release: ReleaseInfo, in work: URL) async throws {
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let dmg = work.appendingPathComponent("Plumb.dmg")
        let base = "\(Self.downloads)/\(release.tag)"

        try await Self.download(URL(string: "\(base)/Plumb.dmg")!, to: dmg) { [weak self] fraction in
            Task { @MainActor in if case .downloading = self?.state { self?.state = .downloading(release, fraction) } }
        }
        let (published, response) = try await URLSession.shared.data(from: URL(string: "\(base)/Plumb.dmg.sha256")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("the update's fingerprint couldn't be downloaded.") }
        let text = String(decoding: published, as: UTF8.self)
        let matches = await Task.detached { Fingerprint.matches(dmg, published: text) }.value  // hashing takes a moment
        guard matches else {
            throw UpdateError("the download doesn't match its published fingerprint.")
        }

        state = .installing(release)
        let volume = work.appendingPathComponent("volume")
        try await Self.run("/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-mountpoint", volume.path, "-quiet")
        let staged = work.appendingPathComponent("Plumb.app")
        var copyError: Error?
        do { try await Self.run("/usr/bin/ditto", volume.appendingPathComponent("Plumb.app").path, staged.path) } catch { copyError = error }
        try? await Self.run("/usr/bin/hdiutil", "detach", volume.path, "-quiet")
        if let copyError { throw copyError }

        let target = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            throw UpdateError("Plumb can't write to \(target.deletingLastPathComponent().path).")
        }
        // A small helper finishes after Plumb quits: swap the apps (keeping the old one until the
        // new one is in place) and reopen Plumb.
        let helper = work.appendingPathComponent("finish-update.sh")
        try """
        #!/bin/bash
        # Logged to ~/Library/Logs/Plumb/update.log, so a failed update can be diagnosed.
        mkdir -p "$HOME/Library/Logs/Plumb"; exec >>"$HOME/Library/Logs/Plumb/update.log" 2>&1
        echo "--- $(date): updating $3"
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        target="$3"; previous="$3.previous"
        rm -rf "$previous"
        incoming="$3.incoming"
        rm -rf "$incoming"
        # Copy (slow) while the old app is still in place, then swap with two instant renames, so
        # there's never a moment without a working Plumb.
        if ditto "$2" "$incoming" && mv "$target" "$previous"; then
          if mv "$incoming" "$target"; then rm -rf "$previous"; echo "updated"
          else echo "swap failed: restoring"; mv "$previous" "$target"; fi
        else echo "could not stage the new app: keeping the current one"; fi
        rm -rf "$incoming"
        open "$target"
        rm -rf "$4"
        """.write(to: helper, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [helper.path, String(ProcessInfo.processInfo.processIdentifier), staged.path, target.path, work.path]
        try process.run()
        NSApp.terminate(nil)
    }

    /// Off the main thread, so the window stays responsive while the new version downloads.
    nonisolated private static func download(_ url: URL, to file: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("the new version couldn't be downloaded.") }
        let total = max(response.expectedContentLength, 1)
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let out = try FileHandle(forWritingTo: file)
        defer { try? out.close() }
        var chunk = Data(capacity: 1 << 20)
        var done: Int64 = 0
        for try await byte in bytes {
            chunk.append(byte)
            if chunk.count == 1 << 20 {
                try out.write(contentsOf: chunk)
                done += Int64(chunk.count)
                chunk.removeAll(keepingCapacity: true)
                progress(min(1, Double(done) / Double(total)))
            }
        }
        try out.write(contentsOf: chunk)
        progress(1)
    }

    /// Runs a command-line tool without blocking the window.
    nonisolated private static func run(_ tool: String, _ arguments: String...) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw UpdateError("\(URL(fileURLWithPath: tool).lastPathComponent) failed.") }
    }
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message.prefix(1).uppercased() + message.dropFirst() }
}
