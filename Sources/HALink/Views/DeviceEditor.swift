import HALinkCore
import SwiftUI

struct DeviceEditor: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DeviceBinding
    @State private var query = ""
    @State private var error: String?
    @State private var confirmingRemoval = false
    private let isNew: Bool

    init(model: AppModel, existing: DeviceBinding? = nil) {
        self.model = model
        isNew = existing == nil
        _draft = State(initialValue: existing ?? DeviceBinding(entityID: "", name: "", action: .toggle))
    }
    private var chosen: HAEntity? { model.entities[draft.entityID] }
    private var matches: [HAEntity] {
        model.selectableEntities.filter { query.isEmpty || $0.name.localizedStandardContains(query) || $0.entityID.localizedStandardContains(query) }
    }
    private var actions: [DeviceAction] {
        if let chosen { return model.availableActions(chosen) }
        return [draft.action]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(isNew ? "添加设备" : "编辑快捷控制").font(.title2.weight(.medium))
                    Text("一个设备可以添加多个动作，分别设置快捷键。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("重新获取设备列表").disabled(!model.canSend)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 10)
            if draft.entityID.isEmpty {
                TextField("搜索设备名称或实体 ID", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                List(matches, selection: Binding(get: { Optional<String>.none }, set: { id in
                    if let id, let entity = model.entities[id], let action = model.availableActions(entity).first {
                        draft.entityID = entity.id; draft.name = entity.name; draft.action = action
                    }
                })) { entity in
                    HStack(spacing: 12) {
                        DeviceIconTile(icon: nil, fallback: entity.icon)
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entity.name)
                            Text(entity.id).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(entity.stateLabel).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 8).tag(entity.id)
                }
                .clipped()
                .overlay {
                    if matches.isEmpty {
                        ContentUnavailableView("没有找到可控制的设备", systemImage: "magnifyingglass", description: Text("试试其他名称，或刷新设备列表。"))
                    }
                }
            } else {
                Form {
                    Section {
                        HStack(spacing: 12) {
                            DeviceIconTile(icon: draft.icon, fallback: chosen?.icon ?? "powerplug",
                                           color: draft.iconColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chosen?.name ?? draft.name).font(.headline.weight(.medium))
                                Text(draft.entityID).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            Spacer()
                            if isNew { Button("重新选择") { draft.entityID = ""; draft.shortcut = nil } }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                    }
                    Section {
                        DeviceEditorRow(title: "显示名称") {
                            TextField("显示名称", text: $draft.name)
                                .labelsHidden()
                                .textFieldStyle(.plain)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 260)
                        }
                        DeviceEditorRow(title: "图标") {
                            DeviceIconPicker(selection: $draft.icon, color: $draft.iconColor,
                                             fallback: chosen?.icon ?? "powerplug")
                        }
                        DeviceEditorRow(title: "执行动作") {
                            Picker("执行动作", selection: $draft.action) {
                                ForEach(actions) { action in Text(action.title).tag(action) }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        ShortcutRecorder(title: "全局快捷键", model: model, bindingID: draft.id, shortcut: $draft.shortcut)
                    }
                    if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }
                }.formStyle(.grouped)
            }
            Divider()
            HStack {
                if !isNew {
                    Button("移除设备…", role: .destructive) { confirmingRemoval = true }
                }
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "添加" : "保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.entityID.isEmpty || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || draft.icon?.isValid == false || model.isRecording)
            }.padding(18)
        }
        .frame(width: 600, height: 540)
        .onDisappear { if model.isRecording { model.endRecording() } }
        .confirmationDialog("移除“\(draft.name)”的快捷控制？", isPresented: $confirmingRemoval) {
            Button("移除", role: .destructive) {
                model.remove(draft.id)
                if !model.devices.contains(where: { $0.id == draft.id }) { dismiss() }
                else { error = model.generalError }
            }
        } message: { Text("只移除 HALink 中的配置，不会删除 HA 设备。") }
    }

    private func save() {
        guard !model.isRecording else { return }
        guard draft.icon?.isValid != false else { error = "请选择图标或输入一个 Emoji。"; return }
        if let shortcut = draft.shortcut {
            model.beginRecording()
            let issue = model.validateShortcut(shortcut, for: draft.id)
            model.endRecording()
            if let issue { error = issue; return }
        }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard model.save(draft) else { error = model.generalError; return }
        dismiss()
    }
}
