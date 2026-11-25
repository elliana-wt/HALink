import AppKit
import HALinkCore
import SwiftUI

struct LightDeviceCard: View {
    let model: AppModel
    let binding: DeviceBinding
    let open: () -> Void
    @State private var brightnessDraft: Double?
    private var entity: HAEntity? { model.entities[binding.entityID] }
    private var pending: Bool { model.busyIDs.contains(binding.id) }
    private var canOpenDetails: Bool { model.supportsDetails(binding) }
    private var canSlide: Bool {
        model.isConnected && entity?.isAvailable == true && entity?.supportsBrightness == true
            && model.services.contains("light.turn_on")
    }
    private var isActive: Bool {
        if let brightnessDraft { return brightnessDraft > 0 }
        return entity?.powerState == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DeviceIconPowerButton(model: model, binding: binding, fallback: "lightbulb")
                VStack(alignment: .leading, spacing: 5) {
                    Text(binding.name).font(.headline).lineLimit(2)
                    Text(summary).font(.caption).foregroundStyle(isActive ? Color.orange : .secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).allowsHitTesting(false)
                if pending { ProgressView().controlSize(.mini).allowsHitTesting(false) }
                if canOpenDetails {
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        .allowsHitTesting(false)
                }
            }
            DeviceCardError(model: model, binding: binding)
        }
        .padding(14)
        .background {
            if canOpenDetails {
                DeviceCardSettingsButton(name: binding.name, action: open)
            } else if model.supportsPowerControl(binding) {
                DeviceCardPowerButton(model: model, binding: binding)
            }
        }
        .modifier(DeviceCardSlider(
            value: entity?.supportsBrightness == true ? entity?.brightnessPercent : nil,
            enabled: canSlide,
            active: isActive,
            pending: pending,
            draft: $brightnessDraft
        ) { value in
            model.setControl(binding.id, .brightness(value))
        })
    }
    private var summary: String {
        guard model.isConnected else { return "未连接" }
        if let brightnessDraft {
            let rounded = Int(brightnessDraft.rounded())
            return rounded == 0 ? "已关闭" : "\(rounded)%"
        }
        return entity.map { DeviceControlStyle.summary($0, unit: model.homeMetadata.temperatureUnit) } ?? "设备已移除"
    }
}

struct ClimateDeviceCard: View {
    let model: AppModel
    let binding: DeviceBinding
    let open: () -> Void
    @Environment(\.usesHomePhoto) private var usesHomePhoto
    @State private var targetDraft: Double?
    private var entity: HAEntity? { model.entities[binding.entityID] }
    private var canOpenDetails: Bool { model.supportsDetails(binding) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DeviceIconPowerButton(model: model, binding: binding, fallback: "air.conditioner.horizontal")
                VStack(alignment: .leading, spacing: 5) {
                    Text(binding.name).font(.headline).lineLimit(2)
                    Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading).allowsHitTesting(false)
                if let entity, entity.supportsTargetTemperature, let target = entity.attributes.temperature,
                   entity.temperatureRange != nil, model.services.contains("climate.set_temperature") {
                    HStack(spacing: 10) {
                        temperatureButton("minus", entity: entity, value: target, direction: -1)
                        Text("\(DeviceControlStyle.number(targetDraft ?? target))°")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .frame(minWidth: 44)
                            .allowsHitTesting(false)
                        temperatureButton("plus", entity: entity, value: target, direction: 1)
                    }
                }
            }
            if model.busyIDs.contains(binding.id) {
                HStack(spacing: 7) { ProgressView().controlSize(.mini); Text("正在更新…").font(.caption).foregroundStyle(.secondary) }
                    .allowsHitTesting(false)
            }
            DeviceCardError(model: model, binding: binding)
        }
        .padding(14)
        .background {
            if canOpenDetails {
                DeviceCardSettingsButton(name: binding.name, action: open)
            } else if model.supportsPowerControl(binding) {
                DeviceCardPowerButton(model: model, binding: binding)
            }
        }
        .modifier(DeviceCardSurface(active: entity?.powerState == true))
        .onChange(of: model.busyIDs.contains(binding.id)) { _, busy in if !busy { targetDraft = nil } }
    }
    private var summary: String {
        guard model.isConnected else { return "未连接" }
        return entity.map { DeviceControlStyle.summary($0, unit: model.homeMetadata.temperatureUnit) } ?? "设备已移除"
    }
    private func temperatureButton(_ symbol: String, entity: HAEntity, value: Double, direction: Double) -> some View {
        let current = targetDraft ?? value
        let atBound = entity.temperatureRange.map { direction < 0 ? current <= $0.lowerBound : current >= $0.upperBound } ?? false
        let isDisabled = !model.isConnected || !entity.isAvailable || atBound
        return Button {
            let next = entity.snappedTemperature(current + direction * entity.temperatureStep)
            targetDraft = next; model.setControl(binding.id, .temperature(next))
        } label: {
            let icon = Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isDisabled ? Color.gray : Color.primary)
                .opacity(isDisabled ? 0.6 : 1)
                .frame(width: 30, height: 30)
            if usesHomePhoto {
                icon
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            } else {
                icon
                    .background(Color.primary.opacity(0.12), in: .circle)
                    .contentShape(.circle)
            }
        }
        .buttonStyle(.plain).disabled(isDisabled)
        .accessibilityLabel("\(binding.name)\(direction > 0 ? "升温" : "降温")")
    }
}

struct OtherDeviceCard: View {
    let model: AppModel
    let binding: DeviceBinding
    @State private var positionDraft: Double?
    private var entity: HAEntity? { model.entities[binding.entityID] }
    private var pending: Bool { model.busyIDs.contains(binding.id) }
    private var canSlideCover: Bool {
        model.isConnected && entity?.isAvailable == true && entity?.supportsCoverPosition == true
            && model.services.contains("cover.set_cover_position")
    }
    private var isActive: Bool {
        if let positionDraft { return positionDraft > 0 }
        if entity?.domain == "cover", let position = entity?.coverPositionPercent { return position > 0 }
        return entity?.powerState == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                DeviceIconTile(icon: binding.icon, fallback: entity?.icon ?? "powerplug", color: binding.iconColor,
                               isActive: isActive)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 5) {
                    Text(binding.name).font(.headline).lineLimit(2)
                    Text(summary)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).allowsHitTesting(false)
                if model.supportsPowerControl(binding) {
                    DevicePowerToggle(model: model, binding: binding).fixedSize()
                } else if pending {
                    ProgressView().controlSize(.mini).allowsHitTesting(false)
                }
            }
            DeviceCardError(model: model, binding: binding)
        }
        .padding(14)
        .background {
            if !model.supportsPowerControl(binding) {
                Button(action: triggerAction) {
                    Color.clear.contentShape(.rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .disabled(!model.isConnected || entity?.isAvailable != true || pending)
                .accessibilityLabel(actionAccessibilityLabel)
                .help(actionAccessibilityLabel)
            }
        }
        .modifier(DeviceCardSlider(
            value: entity?.supportsCoverPosition == true ? entity?.coverPositionPercent : nil,
            enabled: canSlideCover,
            active: isActive,
            pending: pending,
            draft: $positionDraft
        ) { value in
            model.setControl(binding.id, .coverPosition(value))
        })
    }

    private func triggerAction() {
        if canSlideCover {
            let next: Double = isActive ? 0 : 100
            positionDraft = next
            model.setControl(binding.id, .coverPosition(next))
        } else {
            model.run(binding.id)
        }
    }

    private var actionAccessibilityLabel: String {
        if canSlideCover {
            return "\(isActive ? "关闭" : "打开")\(binding.name)"
        }
        return "\(binding.action.title)\(binding.name)"
    }

    private var summary: String {
        guard model.isConnected else { return "未连接" }
        if let positionDraft {
            let rounded = Int(positionDraft.rounded())
            return rounded == 0 ? "已关闭" : "\(rounded)%"
        }
        return entity.map { DeviceControlStyle.summary($0, unit: model.homeMetadata.temperatureUnit) } ?? "设备已移除"
    }
}

private struct DeviceIconPowerButton: View {
    let model: AppModel
    let binding: DeviceBinding
    let fallback: String
    private var entity: HAEntity? { model.entities[binding.entityID] }

    var body: some View {
        Button { model.setPower(binding.id, isOn: entity?.powerState != true) } label: {
            DeviceIconTile(icon: binding.icon, fallback: fallback, color: binding.iconColor,
                           tintOverride: entity.flatMap(DeviceControlStyle.climateTint),
                           isActive: entity?.powerState == true)
                .contentShape(.rect(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .disabled(!model.isConnected || entity?.powerState == nil || model.busyIDs.contains(binding.id) || !model.supportsPowerControl(binding))
        .accessibilityLabel("\(entity?.powerState == true ? "关闭" : "开启")\(binding.name)")
        .help("\(entity?.powerState == true ? "关闭" : "开启")\(binding.name)")
    }
}

private struct DeviceCardSettingsButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        // Keep navigation behind the controls so one click performs only one action.
        Button(action: action) {
            Color.clear.contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开\(name)设置")
        .help("打开\(name)设置")
    }
}

private struct DeviceCardPowerButton: View {
    let model: AppModel
    let binding: DeviceBinding
    private var entity: HAEntity? { model.entities[binding.entityID] }

    var body: some View {
        Button { model.setPower(binding.id, isOn: entity?.powerState != true) } label: {
            Color.clear.contentShape(.rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .disabled(!model.isConnected || entity?.powerState == nil || model.busyIDs.contains(binding.id))
        .accessibilityLabel("\(entity?.powerState == true ? "关闭" : "开启")\(binding.name)")
        .help("\(entity?.powerState == true ? "关闭" : "开启")\(binding.name)")
    }
}

private struct DeviceCardError: View {
    let model: AppModel
    let binding: DeviceBinding
    var body: some View {
        if let error = model.actionErrors[binding.id] ?? model.shortcutErrors[binding.id] {
            Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
        }
    }
}

private struct DeviceCardSlider: ViewModifier {
    let value: Double?
    let enabled: Bool
    let active: Bool
    let pending: Bool
    @Binding var draft: Double?
    let commit: (Double) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var dragging = false
    @State private var cardWidth: CGFloat = 0
    @State private var cursorState = SliderCursorState()
    private static let iconRect = CGRect(x: 14, y: 14, width: 42, height: 42)

    private var currentValue: Double? { draft ?? value }
    private var fraction: Double {
        guard let currentValue else { return 0 }
        return max(0, min(1, currentValue / 100))
    }
    private var activeFillOpacity: Double {
        if colorScheme == .dark {
            return dragging ? 0.30 : 0.22
        }
        return dragging ? 0.86 : 0.72
    }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.primary.opacity(0.045))
                    if currentValue != nil {
                        HorizontalFillShape(fraction: fraction)
                            .fill(Color.white.opacity(activeFillOpacity))
                            .animation(dragging ? nil : .interactiveSpring(duration: 0.2), value: fraction)
                    } else if active {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(activeFillOpacity))
                    }
                }
                .clipShape(.rect(cornerRadius: 20))
                .allowsHitTesting(false)
            }
            .contentShape(.rect(cornerRadius: 20))
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    cursorState.hoverLocation = location
                case .ended:
                    cursorState.hoverLocation = nil
                }
                syncCursor()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                if cardWidth != width {
                    cardWidth = width
                    syncCursor()
                }
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .local)
                    .onChanged { event in
                        guard enabled, cardWidth > 0 else { return }
                        dragging = true
                        draft = max(0, min(100, (event.location.x / cardWidth) * 100)).rounded()
                    }
                    .onEnded { event in
                        guard enabled, cardWidth > 0 else { return }
                        let percent = max(0, min(100, (event.location.x / cardWidth) * 100)).rounded()
                        draft = percent
                        dragging = false
                        commit(percent)
                    },
                isEnabled: enabled
            )
            .onChange(of: dragging) { _, _ in syncCursor() }
            .onChange(of: fraction) { _, _ in syncCursor() }
            .onChange(of: value) { _, _ in if !dragging && !pending { draft = nil } }
            .onChange(of: pending) { _, new in if !new && !dragging { draft = nil } }
            .onChange(of: enabled) { _, new in
                if !new { draft = nil; dragging = false }
                syncCursor()
            }
            .onDisappear { updateCursor(false) }
    }

    private func syncCursor() {
        let shouldShow: Bool
        if !enabled {
            shouldShow = false
        } else if dragging {
            shouldShow = true
        } else if let hoverLocation = cursorState.hoverLocation, cardWidth > 0, fraction > 0,
                  !Self.iconRect.contains(hoverLocation) {
            let edgeX = cardWidth * fraction
            shouldShow = abs(hoverLocation.x - edgeX) <= 10
        } else {
            shouldShow = false
        }
        updateCursor(shouldShow)
    }

    private func updateCursor(_ shouldShow: Bool) {
        guard shouldShow != cursorState.cursorPushed else { return }
        if shouldShow {
            NSCursor.resizeLeftRight.push()
        } else {
            NSCursor.pop()
        }
        cursorState.cursorPushed = shouldShow
    }
}

private final class SliderCursorState {
    var hoverLocation: CGPoint?
    var cursorPushed = false
}

private nonisolated struct HorizontalFillShape: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard fraction > 0 else { return Path() }
        return Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width * fraction, height: rect.height))
    }
}

private struct DeviceCardSurface: ViewModifier {
    let active: Bool
    @Environment(\.colorScheme) private var colorScheme
    private var activeFillOpacity: Double { colorScheme == .dark ? 0.22 : 0.72 }
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(active ? Color.white.opacity(activeFillOpacity) : Color.primary.opacity(0.045))
                    .allowsHitTesting(false)
            }
    }
}
