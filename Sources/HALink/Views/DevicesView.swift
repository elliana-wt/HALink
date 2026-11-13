import HALinkCore
import SwiftUI

struct DevicesView: View {
    @Bindable var model: AppModel
    let openConnection: () -> Void
    @State private var adding = false
    @State private var editor: DeviceBinding?
    @State private var deleting: DeviceBinding?

    var body: some View {
        Form {
            if model.devices.isEmpty {
                ContentUnavailableView {
                    Label("让常用设备，一键响应", systemImage: "keyboard")
                } description: {
                    Text(model.isConnected ? "添加设备，选好动作，再按下你想用的快捷键。" : "先连接 Home Assistant，再选择你想控制的设备。")
                } actions: {
                    Button(model.isConnected ? "添加设备" : "连接 Home Assistant") {
                        if model.isConnected { adding = true } else { openConnection() }
                    }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            } else {
                if !model.isConnected {
                    Section {
                        HStack {
                            Label(model.connectionState.title, systemImage: "wifi.exclamationmark")
                            Spacer()
                            Button("检查连接", action: openConnection)
                        }.font(.callout).foregroundStyle(.secondary)
                    }
                }
                ForEach(model.devices) { binding in
                    Section {
                        DeviceRow(model: model, binding: binding, edit: { editor = binding }, remove: { deleting = binding })
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("我的设备")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("刷新", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .labelStyle(.iconOnly)
                    .help("刷新设备状态")
                    .disabled(!model.canSend)
                Button("添加设备", systemImage: "plus") { adding = true }
                    .labelStyle(.iconOnly)
                    .help("添加设备")
                    .disabled(!model.isConnected)
            }
        }
        .sheet(isPresented: $adding) { DeviceEditor(model: model) }
        .sheet(item: $editor) { binding in DeviceEditor(model: model, existing: binding) }
        .confirmationDialog("移除“\(deleting?.name ?? "")”的快捷控制？", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("移除", role: .destructive) { if let deleting { model.remove(deleting.id) }; deleting = nil }
            } message: { Text("只移除 HALink 中的配置，不会删除 HA 设备。") }
    }
}

private struct DeviceRow: View {
    let model: AppModel
    let binding: DeviceBinding
    let edit: () -> Void
    let remove: () -> Void
    private var entity: HAEntity? { model.entities[binding.entityID] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DeviceIconTile(icon: binding.icon, fallback: entity?.icon ?? "powerplug",
                               color: binding.iconColor, isActive: entity?.powerState == true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(binding.name).font(.headline).lineLimit(1)
                    Text(binding.entityID).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                }
                .layoutPriority(1)
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    Color.clear
                        .frame(width: 14, height: 14)
                        .overlay {
                            if model.busyIDs.contains(binding.id) {
                                ProgressView().controlSize(.mini)
                                    .accessibilityLabel("正在执行\(binding.action.title)")
                            }
                        }
                    Text(binding.action.title)
                }
                .font(.callout).foregroundStyle(.secondary).fixedSize()
                Button(action: edit) {
                    Text(binding.shortcut?.displayName ?? "设置快捷键")
                        .font(.system(.callout, design: .monospaced))
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).help("编辑快捷键").fixedSize()
                if model.supportsPowerControl(binding) {
                    DevicePowerToggle(model: model, binding: binding, showsProgress: false).fixedSize()
                }
                Button(action: edit) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("编辑设备和快捷键")
                .accessibilityLabel("编辑\(binding.name)")
            }
            if let error = model.shortcutErrors[binding.id] ?? model.actionErrors[binding.id] {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(4)
        .contextMenu {
            Button("编辑设备和快捷键…", action: edit)
            Button("移除…", role: .destructive, action: remove)
        }
    }
}
