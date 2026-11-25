import SwiftUI

/// Draft values stay local until the drag ends. The model coalesces repeated keyboard/button input.
struct ControlSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var colors: [Color] = [.orange, .yellow]
    var pending = false
    var enabled = true
    var showsValue = true
    var format: (Double) -> String = { $0.formatted(.number.precision(.fractionLength(0))) }
    var changed: ((Double) -> Void)? = nil
    let commit: (Double) -> Void
    @Environment(\.usesHomePhoto) private var usesHomePhoto
    @Environment(\.homePhotoTheme) private var homePhotoTheme
    @State private var draft: Double?
    @State private var dragging = false
    @FocusState private var focused: Bool

    private var current: Double { max(range.lowerBound, min(range.upperBound, draft ?? value)) }
    private var fraction: Double { (current - range.lowerBound) / (range.upperBound - range.lowerBound) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !title.isEmpty {
                HStack {
                    Text(title).foregroundStyle(.secondary)
                    Spacer()
                    if showsValue {
                        Text(format(current)).monospacedDigit()
                    }
                }.font(.callout)
            }
            HStack(spacing: 10) {
                stepButton("minus", label: "减小\(title)", direction: -1)
                GeometryReader { geometry in
                    let thumbSize = geometry.size.height
                    let travel = max(1, geometry.size.width - thumbSize)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.055))
                        Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: thumbSize + travel * fraction)
                        HStack(spacing: 0) {
                            ForEach(0..<11) { _ in
                                Spacer(minLength: 0)
                                Capsule().fill(Color.primary.opacity(0.13)).frame(width: 1, height: 9)
                            }
                            Spacer(minLength: 0)
                        }.padding(.horizontal, 12)
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                            .opacity(dragging ? 0 : 1)
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
                                    .opacity(dragging ? 1 : 0)
                            }
                            .frame(width: thumbSize, height: thumbSize)
                            .scaleEffect(dragging ? 1.6 : 1)
                            .animation(.spring(duration: 0.22, bounce: 0.2), value: dragging)
                            .offset(x: travel * fraction)
                    }
                    .contentShape(.capsule)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { event in
                            guard enabled else { return }
                            focused = true; dragging = true
                            draft = snapped(range.lowerBound + max(0, min(1, (event.location.x - thumbSize / 2) / travel)) * (range.upperBound - range.lowerBound))
                            changed?(current)
                        }
                        .onEnded { _ in
                            guard enabled else { return }
                            dragging = false
                            commit(current)
                        })
                }
                .frame(height: 42)
                .focusable(enabled)
                .focused($focused)
                .focusEffectDisabled()
                .onKeyPress(.leftArrow) { adjust(-1); return .handled }
                .onKeyPress(.rightArrow) { adjust(1); return .handled }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(title.isEmpty ? "调节值" : title)
                .accessibilityValue(format(current))
                .accessibilityAdjustableAction { direction in adjust(direction == .increment ? 1 : -1) }
                stepButton("plus", label: "增大\(title)", direction: 1)
            }
            HStack {
                Text(format(range.lowerBound))
                Spacer()
                Text(format(range.upperBound))
            }.font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 53)
        }
        .opacity(enabled ? 1 : 0.45)
        .onChange(of: value) { _, _ in if !dragging && !pending { draft = nil } }
        .onChange(of: pending) { _, new in if !new && !dragging { draft = nil } }
        .onChange(of: enabled) { _, new in if !new { draft = nil; dragging = false } }
        .onChange(of: range) { _, _ in draft = nil }
    }

    private func stepButton(_ symbol: String, label: String, direction: Double) -> some View {
        let isDisabled = !enabled || (direction < 0 ? current <= range.lowerBound : current >= range.upperBound)
        return Button { adjust(direction) } label: {
            let icon = Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isDisabled ? Color.gray : Color.primary)
                .opacity(isDisabled ? 0.6 : 1)
                .frame(width: 42, height: 42)
            if usesHomePhoto {
                icon
                    .glassEffect(.regular.interactive(), in: .circle)
                    .contentShape(.circle)
            } else {
                icon
                    .background(.quaternary, in: .circle)
            }
        }
        .buttonStyle(.plain).disabled(isDisabled)
        .accessibilityLabel(label).help(label)
    }
    private func adjust(_ direction: Double) {
        guard enabled else { return }
        draft = snapped(current + direction * step)
        changed?(current)
        commit(current)
    }
    private func snapped(_ value: Double) -> Double {
        let snapped = range.lowerBound + ((value - range.lowerBound) / step).rounded() * step
        return max(range.lowerBound, min(range.upperBound, snapped))
    }
}
