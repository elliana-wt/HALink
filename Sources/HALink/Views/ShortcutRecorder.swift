import AppKit
import Carbon
import HALinkCore
import SwiftUI

struct ShortcutRecorder: View {
    let title: String
    let model: AppModel
    let bindingID: UUID
    @Binding var shortcut: HotKey?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var error: String?
    @State private var hovering = false
    @State private var recorderRegion = ShortcutRecorderRegion()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DeviceEditorRow(title: title) {
                recorder
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDisappear { finish() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in finish() }
    }

    private var recorder: some View {
        Button {
            if recording { finish() } else { begin() }
        } label: {
            Text(recording ? "请按下快捷键…" : (shortcut?.displayName ?? "录入快捷键"))
                .font(.callout)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
        }
        .buttonStyle(.bordered)
        .buttonSizing(.flexible)
        .controlSize(.regular)
        .frame(width: DeviceEditorLayout.shortcutWidth)
        .accessibilityLabel(title)
        .accessibilityValue(recording ? "请按下快捷键…" : (shortcut?.displayName ?? "未设置"))
        .overlay(alignment: .trailing) {
            if (hovering || recording), shortcut != nil {
                Button {
                    shortcut = nil; error = nil; finish()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 24, height: 24)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.trailing, 6)
                .help("清除快捷键")
                .accessibilityLabel("清除快捷键")
            }
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .background(ShortcutRecorderRegionReader(region: recorderRegion))
    }

    private func begin() {
        model.beginRecording(); recording = true; error = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
            let consume = MainActor.assumeIsolated {
                guard event.type == .keyDown else {
                    if !recorderRegion.contains(event) { finish() }
                    return false
                }
                guard !event.isARepeat else { return true }
                let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
                if event.keyCode == 53, flags.isEmpty { finish(); return true }
                if event.keyCode == 48, flags.isEmpty || flags == .shift { finish(); return false }
                if [51,117].contains(event.keyCode), flags.isEmpty { shortcut = nil; finish(); return true }
                var modifiers: UInt32 = 0
                for (flag, carbon) in [(NSEvent.ModifierFlags.command,cmdKey),(.control,controlKey),(.option,optionKey),(.shift,shiftKey)] {
                    if flags.contains(flag) { modifiers |= UInt32(carbon) }
                }
                let labels: [UInt16:String] = [36:"↩",48:"⇥",49:"空格",51:"⌫",53:"⎋",76:"⌤",117:"⌦",123:"←",124:"→",125:"↓",126:"↑"]
                let candidate = HotKey(keyCode: UInt32(event.keyCode), modifiers: modifiers,
                    label: labels[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "")
                if let failure = model.validateShortcut(candidate, for: bindingID) { error = failure }
                else { shortcut = candidate; finish() }
                return true
            }
            return consume ? nil : event
        }
    }
    private func finish() {
        guard recording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil; recording = false; model.endRecording()
    }
}

private final class ShortcutRecorderRegion {
    weak var view: NSView?
    func contains(_ event: NSEvent) -> Bool {
        guard let view, let window = view.window, event.window === window else { return false }
        return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
    }
}

private struct ShortcutRecorderRegionReader: NSViewRepresentable {
    let region: ShortcutRecorderRegion
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        region.view = view
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
