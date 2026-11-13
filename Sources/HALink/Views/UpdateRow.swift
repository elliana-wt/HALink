import SwiftUI

struct UpdateRow: View {
    let model: AppModel
    var body: some View {
        HStack(spacing: 12) {
            Text("版本")
            Spacer()
            status
            Text(model.currentVersion).foregroundStyle(.secondary).monospacedDigit()
            Button("检查更新") { model.checkForUpdates() }
                .disabled(model.updateState == .checking)
        }
    }

    @ViewBuilder private var status: some View {
        switch model.updateState {
        case .idle: EmptyView()
        case .checking: ProgressView().controlSize(.small)
        case .upToDate:
            Text("已是最新版本").font(.caption).foregroundStyle(.secondary)
        case .notPublished:
            Text("尚未发布更新").font(.caption).foregroundStyle(.secondary)
        case .available(let version, let url):
            Link("查看 \(version)", destination: url).font(.caption)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
