import Carbon
import Foundation
import HALinkCore

final class HotKeyManager {
    enum Failure: LocalizedError {
        case conflict
        var errorDescription: String? { "这个快捷键已被系统或其他 App 占用，请换一个。" }
    }
    var onPress: ((UUID) -> Void)?
    private var references: [UUID: EventHotKeyRef] = [:]
    private var identities: [UInt32: UUID] = [:]
    private var handler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private static let signature: OSType = 0x48657374

    isolated deinit { stop() }

    func register(_ shortcut: HotKey, id: UUID) throws {
        guard shortcut.isValid else { throw Failure.conflict }
        try installHandler()
        let eventID = nextID
        nextID &+= 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: eventID),
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
        guard status == noErr, let reference else { throw Failure.conflict }
        unregister(id)
        references[id] = reference
        identities[eventID] = id
    }
    func unregister(_ id: UUID) {
        if let reference = references.removeValue(forKey: id) { UnregisterEventHotKey(reference) }
        identities = identities.filter { $0.value != id }
    }
    func stop() {
        for reference in references.values { UnregisterEventHotKey(reference) }
        references.removeAll(); identities.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
    private func installHandler() throws {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var eventID = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &eventID) == noErr else { return OSStatus(eventNotHandledErr) }
            return MainActor.assumeIsolated {
                guard eventID.signature == HotKeyManager.signature else { return OSStatus(eventNotHandledErr) }
                let owner = Unmanaged<HotKeyManager>.fromOpaque(context).takeUnretainedValue()
                guard let id = owner.identities[eventID.id] else { return OSStatus(eventNotHandledErr) }
                owner.onPress?(id)
                return noErr
            }
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { throw Failure.conflict }
    }
}
