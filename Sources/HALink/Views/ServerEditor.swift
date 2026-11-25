import HALinkCore
import SwiftUI

struct ServerEditor: View {
    let model: AppModel
    let server: ServerConnection?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String
    @State private var token = ""
    @State private var error: String?
    @State private var saving = false
    @State private var removing = false
    @State private var discovery = HADiscovery()

    init(model: AppModel, server: ServerConnection?) {
        self.model = model
        self.server = server
        _name = State(initialValue: server?.name ?? "")
        _address = State(initialValue: server?.address ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(server == nil ? "添加新服务器" : "服务器设定")
                .font(.title2.weight(.medium))
                .padding(22)
            Divider()
            Form {
                if server == nil {
                    Section {
                        HStack {
                            Text("局域网中的 Home Assistant")
                            Spacer()
                            if discovery.searching { ProgressView().controlSize(.small) }
                            Button(discovery.searching ? "停止搜索" : "重新搜索") {
                                if discovery.searching { discovery.stop() } else { discovery.start() }
                            }
                        }
                        ForEach(discovery.servers) { found in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(found.name).fontWeight(.medium)
                                    Text(found.address).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Spacer()
                                Button(address == found.address ? "已填入" : "使用") {
                                    address = found.address
                                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name = found.name }
                                }.disabled(address == found.address)
                            }
                        }
                        if let message = discovery.message {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("选择服务器后，仍需填写访问令牌。")
                    }
                }
                Section {
                    TextField("服务器名称", text: $name, prompt: Text("例如：家里、办公室"))
                    TextField("本地地址", text: $address, prompt: Text("http://192.168.1.10:8123"))
                        .textContentType(.URL).autocorrectionDisabled()
                    SecureField("访问令牌", text: $token, prompt: Text(
                        server != nil && address == server?.address
                            ? "留空可继续使用已保存的 Token" : "粘贴长期访问令牌"
                    ))
                    .autocorrectionDisabled()
                    .onSubmit(save)
                } footer: {
                    Text("在 HA 的“个人资料 → 安全 → 长期访问令牌”中创建 Token。Token 仅保存在这台 Mac 的本机配置目录中，仅当前用户可读写。")
                }
                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section {
                    if let server, server.address == model.address {
                        HStack {
                            Text("当前连接")
                            Spacer()
                            ConnectionBadge(state: model.connectionState)
                        }
                    }
                    Text("保存后连接这台服务器。设备和快捷键按服务器分别管理。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(saving)
            Divider()
            HStack {
                if server != nil {
                    Button("移除服务器…", role: .destructive) { removing = true }
                        .tint(.red)
                        .foregroundStyle(.red)
                        .disabled(saving)
                }
                Spacer()
                if saving { ProgressView().controlSize(.small) }
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction).disabled(saving)
                Button("保存并连接", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(18)
        }
        .frame(width: 580, height: server == nil ? 610 : 440)
        .task { if server == nil { discovery.start() } }
        .onDisappear { discovery.stop() }
        .interactiveDismissDisabled(saving)
        .confirmationDialog("移除“\(server?.name ?? "")”？", isPresented: $removing) {
            Button("移除服务器", role: .destructive) {
                guard let server else { return }
                if model.removeServer(server.id) { dismiss() }
                else { error = model.connectionError }
            }
        } message: {
            Text("这会移除 HALink 保存的连接、Token 和对应的设备快捷键，不会删除 Home Assistant 中的设备。")
        }
    }

    private func save() {
        guard !saving else { return }
        saving = true; error = nil
        Task {
            let success = await model.connect(serverID: server?.id, name: name, address: address, token: token)
            saving = false
            if success { token = ""; dismiss() }
            else { error = model.connectionError ?? "连接未完成，请稍后重试。" }
        }
    }
}
