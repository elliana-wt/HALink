import AppKit
import HALinkCore
import SwiftUI

struct LightControls: View {
    let model: AppModel
    let binding: DeviceBinding
    let entity: HAEntity
    @State private var brightnessDraft: Double?
    @State private var colorTempDraft: Double?
    private var enabled: Bool { model.isConnected && entity.isAvailable }
    private var pending: Bool { model.busyIDs.contains(binding.id) }
    private var showsBrightness: Bool { entity.supportsBrightness && model.services.contains("light.turn_on") }
    private var showsColorTemperature: Bool { entity.colorTemperatureRange != nil && model.services.contains("light.turn_on") }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if showsBrightness || showsColorTemperature {
                HStack(alignment: .top, spacing: 16) {
                    if showsBrightness {
                        let brightness = brightnessDraft ?? entity.brightnessPercent
                        lightMetric(
                            title: "亮度",
                            number: brightness.map { String(Int($0.rounded())) } ?? "—",
                            unit: brightness == nil ? "" : "%"
                        )
                    }
                    if showsColorTemperature {
                        let colorTemp = colorTempDraft ?? entity.colorTemperature
                        lightMetric(
                            title: "色温",
                            number: colorTemp.map { String(Int($0.rounded())) } ?? "—",
                            unit: colorTemp == nil ? "" : "K"
                        )
                    }
                }
            }
            if showsBrightness {
                ControlSlider(title: "亮度", value: entity.brightnessPercent ?? 0, range: 0...100,
                              colors: [Color(red: 1.0, green: 0.76, blue: 0.24)], pending: pending, enabled: enabled,
                              showsValue: false, format: { "\(Int($0.rounded()))%" },
                              changed: { brightnessDraft = $0 }) {
                    model.setControl(binding.id, .brightness($0))
                }
            }
            if let range = entity.colorTemperatureRange, model.services.contains("light.turn_on") {
                ControlSlider(title: "色温", value: entity.colorTemperature ?? range.lowerBound, range: range,
                              step: 1, colors: [.orange, .yellow.opacity(0.5), .cyan.opacity(0.5)],
                              pending: pending, enabled: enabled, showsValue: false,
                              format: { "\(Int($0.rounded()))K" },
                              changed: { colorTempDraft = $0 }) {
                    model.setControl(binding.id, .colorTemperature($0))
                }
            }
            if entity.supportsColor, model.services.contains("light.turn_on") {
                LightColorControl(entity: entity, pending: pending, enabled: enabled) { hue, saturation in
                    model.setControl(binding.id, .color(hue: hue, saturation: saturation))
                }
            }
            if !entity.supportsBrightness && !entity.supportsColor && entity.colorTemperatureRange == nil {
                Text("这盏灯支持开关控制。")
                    .font(.callout).foregroundStyle(.secondary).padding(.vertical, 20)
            }
        }
        .onChange(of: pending) { _, new in
            if !new {
                brightnessDraft = nil
                colorTempDraft = nil
            }
        }
    }

    private func lightMetric(title: String, number: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("\(Text(number).tracking(-2))\(unit)")
                .font(.system(size: 52, weight: .medium, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LightColorControl: View {
    let entity: HAEntity
    let pending: Bool
    let enabled: Bool
    let commit: (Double, Double) -> Void
    @State private var draft: CGPoint?
    @State private var dragging = false
    private let hues: [Double] = [0, 30, 52, 140, 215, 265]

    private var point: CGPoint {
        if let draft { return draft }
        if let hs = entity.attributes.hsColor, hs.count >= 2 { return CGPoint(x: hs[0] / 360, y: 1 - hs[1] / 100) }
        if let rgb = entity.attributes.rgbColor, rgb.count >= 3,
           let color = NSColor(srgbRed: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255, alpha: 1).usingColorSpace(.sRGB) {
            return CGPoint(x: color.hueComponent, y: 1 - color.saturationComponent)
        }
        return CGPoint(x: 0, y: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("颜色").foregroundStyle(.secondary)
                Spacer()
                Circle().fill(Color(hue: point.x, saturation: 1 - point.y, brightness: 1)).frame(width: 16, height: 16)
                Text(entity.attributes.colorMode == "color_temp" ? "色温模式" : "彩色模式")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: (0...12).map { Color(hue: Double($0) / 12, saturation: 1, brightness: 1) },
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [.white.opacity(0), .white],
                                                                                             startPoint: .top, endPoint: .bottom))
                    }
                    .overlay(alignment: .topLeading) {
                        Circle().fill(Color(hue: point.x, saturation: 1 - point.y, brightness: 1))
                            .frame(width: 23, height: 23).overlay { Circle().stroke(.white, lineWidth: 3) }
                            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                            .offset(x: 13 + point.x * (geometry.size.width - 26) - 11.5,
                                    y: 13 + point.y * (geometry.size.height - 26) - 11.5)
                    }
                    .contentShape(.rect(cornerRadius: 18))
                    .gesture(DragGesture(minimumDistance: 0).onChanged { event in
                        guard enabled else { return }
                        dragging = true
                        draft = CGPoint(x: max(0, min(1, (event.location.x - 13) / (geometry.size.width - 26))),
                                        y: max(0, min(1, (event.location.y - 13) / (geometry.size.height - 26))))
                    }.onEnded { _ in
                        guard enabled else { return }
                        dragging = false; commit(point.x * 360, (1 - point.y) * 100)
                    })
            }.frame(height: 104)
                .accessibilityLabel("颜色选择区，可用下方常用颜色调节")
            HStack(spacing: 9) {
                ForEach(hues, id: \.self) { hue in
                    Button {
                        draft = CGPoint(x: hue / 360, y: 0.1)
                        commit(hue, 90)
                    } label: {
                        RoundedRectangle(cornerRadius: 9).fill(Color(hue: hue / 360, saturation: 0.9, brightness: 1))
                            .frame(maxWidth: .infinity).frame(height: 28)
                            .overlay { RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.25), lineWidth: 1) }
                    }.buttonStyle(.plain).accessibilityLabel("\(colorName(hue))色")
                }
            }.disabled(!enabled)
        }
        .opacity(enabled ? 1 : 0.45)
        .onChange(of: pending) { _, new in if !new && !dragging { draft = nil } }
        .onChange(of: entity.attributes.hsColor) { _, _ in if !pending && !dragging { draft = nil } }
        .onChange(of: entity.attributes.rgbColor) { _, _ in if !pending && !dragging { draft = nil } }
    }
    private func colorName(_ hue: Double) -> String {
        switch hue { case 0: "红"; case 30: "橙"; case 52: "黄"; case 140: "绿"; case 215: "蓝"; default: "紫" }
    }
}
