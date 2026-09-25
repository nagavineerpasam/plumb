import SwiftUI

/// First launch: the language models download once, then the app works offline.
struct Onboarding: View {
    let downloaded: Int64
    let total: Int64
    let problem: String?

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, isActive: problem == nil)
            Text("Setting up Writing Signals").font(.title.weight(.semibold))
            Text("Downloading the language models once. After this everything runs on your Mac, offline and private.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            VStack(spacing: 6) {
                ProgressView(value: Double(downloaded), total: Double(max(total, 1)))
                    .frame(width: 320)
                Text("\(bytes(downloaded)) of \(bytes(total))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let problem {
                Label(problem, systemImage: "wifi.exclamationmark")
                    .font(.callout).foregroundStyle(.orange)
                    .frame(maxWidth: 380)
                Text("Retrying automatically. The download resumes where it stopped.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
