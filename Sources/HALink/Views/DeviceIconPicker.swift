import AppKit
import HALinkCore
import SwiftUI

struct DeviceIconPicker: View {
    @Binding var selection: DeviceIcon?
    @Binding var color: DeviceIconColor?
    let fallback: String
    @State private var showingPicker = false

    private enum Kind: String, CaseIterable {
        case symbol = "图标", emoji = "Emoji"
    }

    private static let symbols: [(name: String, title: String)] = [
        ("lightbulb", "灯泡"), ("lamp.desk", "台灯"), ("lamp.ceiling", "吊灯"),
        ("lamp.floor", "落地灯"), ("sun.max", "太阳"), ("moon", "月亮"),
        ("powerplug", "插座"), ("power", "电源"), ("switch.2", "开关"),
        ("fan", "风扇"), ("air.conditioner.horizontal", "空调"), ("thermometer.medium", "温度"),
        ("blinds.horizontal.closed", "百叶窗"), ("curtains.closed", "窗帘"), ("door.left.hand.closed", "门"),
        ("window.vertical.closed", "窗户"), ("lock", "锁"), ("camera", "摄像头"),
        ("tv", "电视"), ("hifispeaker", "音箱"), ("music.note", "音乐"),
        ("play.square", "播放"), ("sparkles", "场景"), ("button.programmable", "按钮"),
        ("house", "房屋"), ("bed.double", "卧室"), ("sofa", "客厅"),
        ("desktopcomputer", "电脑"), ("drop", "水滴"), ("flame", "火焰")
    ]

    var body: some View {
        Button("选择图标或 Emoji") { showingPicker = true }
            .fixedSize()
            .accessibilityLabel("选择设备图标或 Emoji")
            .popover(isPresented: $showingPicker) { picker }
    }

    private var kind: Binding<Kind> {
        Binding {
            switch selection {
            case nil, .symbol: .symbol
            case .emoji: .emoji
            }
        } set: { kind in
            switch kind {
            case .symbol: selection = .symbol(fallback)
            case .emoji: selection = .emoji("💡")
            }
        }
    }

    private var selectedSymbol: String? {
        switch selection {
        case nil: fallback
        case .symbol(let name): name
        case .emoji: nil
        }
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("图标类型", selection: kind) {
                ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch kind.wrappedValue {
            case .symbol:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                    ForEach(Self.symbols, id: \.name) { symbol in
                        Button { selection = .symbol(symbol.name) } label: {
                            DeviceIconView(icon: .symbol(symbol.name), fallback: fallback, color: color)
                                .frame(width: 38, height: 38)
                                .background(selectedSymbol == symbol.name ? Color.primary.opacity(0.1) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol.title)
                        .accessibilityValue(selectedSymbol == symbol.name ? "已选择" : "")
                        .help(symbol.title)
                    }
                }
                HStack {
                    ColorPicker("图标颜色", selection: Binding(
                        get: { color?.swiftUIColor ?? .orange },
                        set: { color = DeviceIconColor(color: $0) }
                    ), supportsOpacity: false)
                    if color != nil {
                        Button("恢复默认") { color = nil }
                            .fixedSize()
                    }
                }
            case .emoji:
                HStack(spacing: 12) {
                    TextField("Emoji", text: Binding(
                        get: { if case .emoji(let value) = selection { value } else { "" } },
                        set: { selection = .emoji($0) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.leading)
                    .frame(width: 88)
                    .accessibilityLabel("输入或粘贴一个 Emoji")
                    Button("选择表情或符号") { NSApp.orderFrontCharacterPalette(nil) }
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selection?.isValid == false {
                    Text("请输入一个 Emoji，支持肤色、旗帜和组合表情。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("完成") { showingPicker = false }
                    .disabled(selection?.isValid == false)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
