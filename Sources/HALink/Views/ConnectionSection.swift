import HALinkCore
import SwiftUI

struct ConnectionSection: View {
    @Bindable var model: AppModel
    @State private var editor: ServerEditorRequest?

    var body: some View {
        Section {
            if model.servers.isEmpty {
                Text("尚未添加服务器").foregroundStyle(.secondary)
            } else {
                ForEach(model.servers) { server in
                    Button { editor = ServerEditorRequest(server: server) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name).foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(server.address).font(.caption).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 12)
                            if server.address == model.address {
                                ConnectionBadge(state: model.connectionState).font(.caption)
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("设定\(server.name)")
                }
            }
        } header: {
            Text("Home Assistant 连接")
        } footer: {
            HStack {
                Spacer()
                Button("添加新服务器") { editor = ServerEditorRequest(server: nil) }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .font(.body)
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .sheet(item: $editor) { request in
            ServerEditor(model: model, server: request.server)
        }
    }
}

private struct ServerEditorRequest: Identifiable {
    let id = UUID()
    let server: ServerConnection?
}
