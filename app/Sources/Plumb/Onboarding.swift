import SwiftUI

/// First launch: the writing model downloads once, then the app works offline. Three steps tick
/// off in turn, so it's always clear what's happening and it never looks stuck at 100%.
struct Onboarding: View {
    /// 0 downloading, 1 unpacking, 2 starting the checker.
    let step: Int
    let downloaded: Int64
    let total: Int64
    let problem: String?

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "text.badge.checkmark")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse, isActive: problem == nil)
            Text("Setting up Plumb").font(.title.weight(.semibold))
            Text("This happens only once. After this, everything runs on your Mac, offline and private.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            VStack(alignment: .leading, spacing: 14) {
                row(0, "Downloading the writing model", detail: total > 0 ? "\(bytes(downloaded)) of \(bytes(total))" : "About 800 MB")
                if step == 0 {
                    ProgressView(value: Double(downloaded), total: Double(max(total, 1)))
                        .padding(.leading, 30)
                }
                row(1, "Unpacking", detail: nil)
                row(2, "Starting the checker", detail: nil)
            }
            .frame(width: 360)
            .padding(20)
            .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        .animation(.smooth, value: step)
    }

    /// One step: ticked when done, spinning while it runs, an empty circle while it waits.
    private func row(_ index: Int, _ title: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Group {
                if index < step {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if index == step {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18)
            Text(title).foregroundStyle(index <= step ? .primary : .secondary)
            Spacer()
            if let detail, index == step {
                Text(detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }

    private func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
