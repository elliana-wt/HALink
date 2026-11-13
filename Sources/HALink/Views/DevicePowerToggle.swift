import HALinkCore
import SwiftUI

struct DevicePowerToggle: View {
    let model: AppModel
    let binding: DeviceBinding
    var showsProgress = true
    private var entity: HAEntity? { model.entities[binding.entityID] }

    var body: some View {
        HStack(spacing: 7) {
            if showsProgress, model.busyIDs.contains(binding.id) {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("正在更新设备状态")
            }
            Toggle(binding.name, isOn: Binding(
                get: { entity?.powerState ?? false },
                set: { model.setPower(binding.id, isOn: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("\(binding.name)电源")
            .help("直接打开或关闭\(binding.name)")
            .disabled(!model.isConnected || entity?.powerState == nil || model.busyIDs.contains(binding.id))
        }
    }
}
