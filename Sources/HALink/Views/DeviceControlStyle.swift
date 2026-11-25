import HALinkCore
import SwiftUI

enum DeviceControlStyle {
    static func number(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(0...1))) ?? "—"
    }
    static func title(_ raw: String) -> String {
        switch raw {
        case "off": "关闭"
        case "on": "开启"
        case "heat": "制热"
        case "cool": "制冷"
        case "heat_cool": "冷暖自动"
        case "auto": "自动"
        case "fan_only", "fan": "送风"
        case "dry", "drying": "除湿"
        case "idle": "待机"
        case "heating": "制热中"
        case "cooling": "制冷中"
        case "preheating": "预热中"
        case "defrosting": "除霜中"
        case "low": "低速"
        case "medium", "middle": "中速"
        case "high": "高速"
        case "eco": "节能"
        case "sleep": "睡眠"
        case "none": "无"
        case "away": "离家"
        case "home": "在家"
        case "comfort": "舒适"
        case "boost": "强力"
        case "vertical": "上下"
        case "horizontal": "左右"
        case "both": "上下及左右"
        default: raw
        }
    }
    static func summary(_ entity: HAEntity, unit: String) -> String {
        if !entity.isAvailable { return entity.stateLabel }
        if entity.powerState == false { return "已关闭" }
        if entity.domain == "light", let brightness = entity.brightnessPercent {
            return "\(Int(brightness.rounded()))%"
        }
        if entity.domain == "cover", entity.supportsCoverPosition, let position = entity.coverPositionPercent {
            let rounded = Int(position.rounded())
            return rounded == 0 ? "已关闭" : "\(rounded)%"
        }
        if entity.domain == "climate" {
            let mode = title(entity.attributes.hvacAction ?? entity.state)
            if let room = entity.attributes.currentTemperature { return "\(mode) · 室温 \(number(room))\(unit)" }
            return mode
        }
        return entity.stateLabel
    }

    static func climateTint(for entity: HAEntity) -> Color? {
        guard entity.domain == "climate", entity.powerState == true else { return nil }
        switch entity.attributes.hvacAction {
        case "heating", "preheating": return .orange
        case "cooling": return .blue
        default: break
        }
        switch entity.state {
        case "heat": return .orange
        case "cool": return .blue
        default: return nil
        }
    }
}

struct ControlPowerButton: View {
    let model: AppModel
    let binding: DeviceBinding
    @Environment(\.homePhotoTheme) private var homePhotoTheme
    @State private var draft: Bool?
    @State private var lastTriggerAt: Date = .distantPast
    private var entity: HAEntity? { model.entities[binding.entityID] }
    private var actualOn: Bool { entity?.powerState == true }
    private var displayedOn: Bool { draft ?? actualOn }
    private var pending: Bool { model.busyIDs.contains(binding.id) }
    private var accentColor: Color {
        homePhotoTheme?.accentColor ?? .orange
    }
    private var isDisabled: Bool {
        !model.isConnected || entity?.powerState == nil || pending || !model.supportsPowerControl(binding)
    }

    var body: some View {
        Toggle(binding.name, isOn: Binding(
            get: { displayedOn },
            set: { commitPower($0) }
        ))
        .labelsHidden()
        .toggleStyle(CircularSlidingToggleStyle(accentColor: accentColor))
        .disabled(isDisabled)
        .accessibilityLabel("\(binding.name)：\(displayedOn ? "关闭" : "开启")")
        .help(displayedOn ? "关闭设备" : "开启设备")
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

private struct CircularSlidingToggleStyle: ToggleStyle {
    let accentColor: Color

    func makeBody(configuration: ToggleStyleConfiguration) -> some View {
        CircularSlidingToggleBody(
            isOn: configuration.$isOn,
            accentColor: accentColor
        )
    }
}

private struct CircularSlidingToggleBody: View {
    @Binding var isOn: Bool
    let accentColor: Color
    @Environment(\.isEnabled) private var isEnabled
    @State private var dragFraction: CGFloat?
    @State private var isPressed = false

    private let trackWidth: CGFloat = 56
    private let trackHeight: CGFloat = 34
    private let thumbInset: CGFloat = 3
    private var thumbSize: CGFloat { trackHeight - thumbInset * 2 }
    private var travel: CGFloat { trackWidth - thumbSize - thumbInset * 2 }

    var body: some View {
        let fraction = dragFraction ?? (isOn ? 1 : 0)

        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.18))
                .overlay {
                    Capsule()
                        .fill(accentColor)
                        .opacity(fraction)
                        .animation(dragFraction == nil ? .easeInOut(duration: 0.28) : nil, value: fraction)
                }
                .frame(width: trackWidth, height: trackHeight)
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
                .opacity(isPressed ? 0 : 1)
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.85), .white.opacity(0.25), .white.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.25
                        )
                        .opacity(isPressed ? 1 : 0)
                }
                .frame(width: thumbSize, height: thumbSize)
                .scaleEffect(isPressed ? 1.85 : 1)
                .offset(x: thumbInset + travel * fraction)
                .animation(dragFraction == nil ? .spring(duration: 0.26, bounce: 0.15) : nil, value: fraction)
        }
        .frame(width: trackWidth, height: trackHeight)
        .contentShape(.capsule)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.spring(duration: 0.22, bounce: 0.2), value: isPressed)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard isEnabled else { return }
                    if !isPressed { isPressed = true }
                    if abs(value.translation.width) >= 4 {
                        let base: CGFloat = isOn ? 1 : 0
                        dragFraction = max(0, min(1, base + value.translation.width / travel))
                    }
                }
                .onEnded { _ in
                    guard isEnabled else { return }
                    let target: Bool
                    if let currentFraction = dragFraction {
                        target = currentFraction >= 0.5
                    } else {
                        target = !isOn
                    }
                    if target != isOn {
                        isOn = target
                    }
                    isPressed = false
                    dragFraction = nil
                }
        )
    }
}
