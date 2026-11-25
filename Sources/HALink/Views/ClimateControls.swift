import HALinkCore
import SwiftUI

struct ClimateControls: View {
    let model: AppModel
    let binding: DeviceBinding
    let entity: HAEntity
    @State private var targetDraft: Double?
    @Environment(\.homePhotoTheme) private var homePhotoTheme
    private var enabled: Bool { model.isConnected && entity.isAvailable }
    private var pending: Bool { model.busyIDs.contains(binding.id) }
    private var unit: String { model.homeMetadata.temperatureUnit }
    private var a: HAEntity.Attributes { entity.attributes }
    private var climateTint: Color? { DeviceControlStyle.climateTint(for: entity) }
    private var temperatureColor: Color { climateTint ?? .primary }
    private var accentColor: Color { climateTint ?? homePhotoTheme?.accentColor ?? .primary }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                temperatureMetric(
                    title: "设定温度",
                    value: entity.supportsTargetRange
                        ? "\(DeviceControlStyle.number(a.targetTempLow))–\(DeviceControlStyle.number(a.targetTempHigh))"
                        : DeviceControlStyle.number(targetDraft ?? a.temperature),
                    fontSize: entity.supportsTargetRange ? 36 : 52
                )
                if let room = a.currentTemperature {
                    temperatureMetric(
                        title: "室内温度",
                        value: DeviceControlStyle.number(room),
                        fontSize: 52
                    )
                }
            }
            if let range = entity.temperatureRange, model.services.contains("climate.set_temperature") {
                if entity.supportsTargetRange, let low = a.targetTempLow, let high = a.targetTempHigh {
                    temperatureSlider("温度下限", value: low, range: range) {
                        model.setControl(binding.id, .temperatureLow($0))
                    }
                    temperatureSlider("温度上限", value: high, range: range) {
                        model.setControl(binding.id, .temperatureHigh($0))
                    }
                } else if entity.supportsTargetTemperature {
                    temperatureSlider("目标温度", value: a.temperature ?? range.lowerBound, range: range) {
                        model.setControl(binding.id, .temperature($0))
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                if let modes = a.hvacModes, !modes.isEmpty, model.services.contains("climate.set_hvac_mode") {
                    choice("模式", icon: "thermometer.medium", current: entity.state, options: modes, control: HAControl.hvacMode)
                }
                if entity.hasFeature(8), let modes = a.fanModes, !modes.isEmpty, model.services.contains("climate.set_fan_mode") {
                    choice("风速", icon: "fan", current: a.fanMode, options: modes, control: HAControl.fanMode)
                }
                if entity.hasFeature(32), let modes = a.swingModes, !modes.isEmpty, model.services.contains("climate.set_swing_mode") {
                    choice("摆风", icon: "wind", current: a.swingMode, options: modes, control: HAControl.swingMode)
                }
                if entity.hasFeature(512), let modes = a.swingHorizontalModes, !modes.isEmpty,
                   model.services.contains("climate.set_swing_horizontal_mode") {
                    choice("水平摆风", icon: "arrow.left.and.right", current: a.swingHorizontalMode, options: modes, control: HAControl.horizontalSwingMode)
                }
                if entity.hasFeature(16), let presets = a.presetModes, !presets.isEmpty, model.services.contains("climate.set_preset_mode") {
                    choice("预设", icon: "leaf", current: a.presetMode, options: presets, control: HAControl.preset)
                }
            }
        }
        .onChange(of: pending) { _, new in if !new { targetDraft = nil } }
    }

    private func temperatureMetric(title: String, value: String, fontSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("\(Text(value).tracking(-2))\(unit)")
                .font(.system(size: fontSize, weight: .medium, design: .rounded))
                .foregroundStyle(temperatureColor)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var temperatureSliderColor: Color {
        if let action = entity.attributes.hvacAction, ["heating", "preheating"].contains(action) {
            return .orange
        }
        return entity.state == "heat" ? .orange : .blue
    }

    private func temperatureSlider(_ title: String, value: Double, range: ClosedRange<Double>, commit: @escaping (Double) -> Void) -> some View {
        ControlSlider(title: title, value: value, range: range, step: entity.temperatureStep,
                      colors: [temperatureSliderColor], pending: pending, enabled: enabled,
                      showsValue: entity.supportsTargetRange,
                      format: { "\(DeviceControlStyle.number($0))\(unit)" },
                      changed: { if entity.supportsTargetTemperature { targetDraft = $0 } }, commit: commit)
    }
    private func choice(_ title: String, icon: String, current: String?, options: [String], control: @escaping (String) -> HAControl) -> some View {
        Menu {
            ForEach(options, id: \.self) { value in
                Button { model.setControl(binding.id, control(value)) } label: {
                    if current == value { Label(DeviceControlStyle.title(value), systemImage: "checkmark") }
                    else { Text(DeviceControlStyle.title(value)) }
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Image(systemName: icon).font(.title3).foregroundStyle(accentColor)
                    Spacer()
                    Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(current.map(DeviceControlStyle.title) ?? "—").font(.headline).lineLimit(1)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.055), in: .rect(cornerRadius: 17))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
        .disabled(!enabled).accessibilityLabel("\(title)：\(current.map(DeviceControlStyle.title) ?? "未知")")
    }
}
