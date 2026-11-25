import HALinkCore
import SwiftUI

struct DevicePowerToggle: View {
    let model: AppModel
    let binding: DeviceBinding
    var showsProgress = true
    @State private var draft: Bool?
    @State private var lastTriggerAt: Date = .distantPast
    private var entity: HAEntity? { model.entities[binding.entityID] }
    private var actualOn: Bool { entity?.powerState ?? false }
    private var displayedOn: Bool { draft ?? actualOn }
    private var pending: Bool { model.busyIDs.contains(binding.id) }

    var body: some View {
        HStack(spacing: 7) {
            if showsProgress, pending {
                ProgressView().controlSize(.mini)
                    .accessibilityLabel("正在更新设备状态")
            }
            Toggle(binding.name, isOn: Binding(
                get: { displayedOn },
                set: { commitPower($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("\(binding.name)电源")
            .help("直接打开或关闭\(binding.name)")
            .disabled(!model.isConnected || entity?.powerState == nil || pending)
        }
        .onChange(of: actualOn) { _, new in
            if draft == new { draft = nil }
        }
        .onChange(of: pending) { _, isPending in
            if !isPending { draft = nil }
        }
        .onChange(of: binding.id) { _, _ in
            draft = nil
        }
    }

    private func commitPower(_ target: Bool) {
        let now = Date()
        guard now.timeIntervalSince(lastTriggerAt) >= 0.45 else { return }
        lastTriggerAt = now
        model.setPower(binding.id, isOn: target)
        if model.busyIDs.contains(binding.id) {
            draft = target
        }
    }
}
