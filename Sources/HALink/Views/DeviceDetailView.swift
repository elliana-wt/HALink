import HALinkCore
import SwiftUI

struct DeviceDetailView: View {
    let model: AppModel
    let binding: DeviceBinding
    let back: () -> Void
    @Environment(\.usesHomePhoto) private var usesHomePhoto
    private var entity: HAEntity? { model.entities[binding.entityID] }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 12) {
                Button(action: back) {
                    if usesHomePhoto {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium))
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular.interactive(), in: .circle)
                            .contentShape(.circle)
                    } else {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .medium))
                            .frame(width: 36, height: 36).background(.quaternary, in: .circle)
                    }
                }.buttonStyle(.plain).accessibilityLabel("返回设备列表").help("返回设备列表")
                VStack(alignment: .leading, spacing: 5) {
                    Text(binding.name).font(.title3.weight(.medium)).lineLimit(2)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if model.busyIDs.contains(binding.id) { ProgressView().controlSize(.small) }
                ControlPowerButton(model: model, binding: binding)
            }
            if let entity {
                if entity.domain == "light" { LightControls(model: model, binding: binding, entity: entity) }
                if entity.domain == "climate" { ClimateControls(model: model, binding: binding, entity: entity) }
                if !entity.isAvailable {
                    Label("设备当前不可用，恢复连接后可继续控制。", systemImage: "wifi.exclamationmark")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView("设备已移除", systemImage: "questionmark.circle",
                                       description: Text("返回列表，或在设置中重新选择设备。"))
            }
            if let error = model.actionErrors[binding.id] {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.isConnected {
                Label("连接中断，正在尝试重新连接。", systemImage: "wifi.exclamationmark")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(8)
    }
    private var subtitle: String {
        let room = model.areaName(for: binding.entityID)
        let status = entity.map { DeviceControlStyle.summary($0, unit: model.homeMetadata.temperatureUnit) } ?? "设备已移除"
        return [room, status].compactMap { $0 }.joined(separator: " · ")
    }
}
