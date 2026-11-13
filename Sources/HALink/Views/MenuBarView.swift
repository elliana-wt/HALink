import AppKit
import HALinkCore
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: AppModel
    let showSettings: (SettingsPage) -> Void
    let contentHeightChanged: (CGFloat) -> Void

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                header
                if model.devices.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.devices.enumerated()), id: \.element.id) { index, binding in
                            if index > 0 {
                                Divider().padding(.horizontal, 14)
                            }
                            MenuDeviceRow(model: model, binding: binding)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.045))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if let error = model.connectionError, model.connectionState == .offline {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6)
                }
                footer
            }
            .padding(14)
            .frame(width: MenuBarLayout.width, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeightChanged($0) }
        }
        .defaultScrollAnchor(.top)
        .frame(width: MenuBarLayout.width, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: MenuBarLayout.cornerRadius))
        .contentShape(.rect(cornerRadius: MenuBarLayout.cornerRadius))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.currentServerName).font(.title2.weight(.bold))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                ConnectionBadge(state: model.connectionState).font(.caption)
            }
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Label("刷新设备", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless).disabled(!model.canSend).help("刷新设备状态")
        }.padding(.horizontal, 8).padding(.top, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("还没有添加设备").font(.headline)
            Text(model.isConnected ? "添加常用设备，即可在这里快速控制。" : "先在设置中连接 Home Assistant。")
                .font(.callout).foregroundStyle(.secondary)
            Button(model.isConnected ? "添加设备" : "打开设置") {
                showSettings(model.isConnected ? .devices : .settings)
            }.buttonStyle(.bordered)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 22)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button { showSettings(.settings) } label: { Label("设置", systemImage: "gearshape") }
            Spacer()
            Button { NSApp.terminate(nil) } label: { Label("退出", systemImage: "power") }
                .help("退出 HALink")
        }
        .buttonStyle(.borderless).padding(.horizontal, 6).padding(.vertical, 3)
    }
}

private struct MenuDeviceRow: View {
    let model: AppModel
    let binding: DeviceBinding
    private var entity: HAEntity? { model.entities[binding.entityID] }
    private var error: String? { model.actionErrors[binding.id] ?? model.shortcutErrors[binding.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                DeviceIconTile(icon: binding.icon, fallback: entity?.icon ?? "powerplug",
                               color: binding.iconColor, isActive: entity?.powerState == true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(binding.name).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if model.supportsPowerControl(binding) {
                    DevicePowerToggle(model: model, binding: binding)
                } else {
                    Button { model.run(binding.id) } label: {
                        if model.busyIDs.contains(binding.id) {
                            ProgressView().controlSize(.small).frame(width: 32, height: 18)
                        } else { Text(actionLabel).frame(minWidth: 32) }
                    }
                    .disabled(!model.canSend || model.busyIDs.contains(binding.id))
                    .accessibilityLabel("\(binding.name)：\(binding.action.title)").help(binding.action.title)
                }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var status: String {
        if !model.isConnected { return "未连接" }
        return entity?.stateLabel ?? "设备已移除"
    }
    private var actionLabel: String {
        switch binding.action {
        case .toggle: "切换"
        case .turnOn: ["scene", "script"].contains(entity?.domain ?? "") ? "执行" : "开启"
        case .turnOff: "关闭"
        case .open: "打开"
        case .close: "关闭"
        case .stop: "停止"
        case .playPause: "播放/暂停"
        case .next: "下一曲"
        case .previous: "上一曲"
        case .press: "执行"
        }
    }
}
