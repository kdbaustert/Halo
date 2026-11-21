import Carbon.HIToolbox

/// A system-wide shortcut through Carbon's hot key API, which needs no Accessibility permission
/// because it only ever sees the combination it registered.
@MainActor
final class GlobalHotKey {
    enum RegistrationError: Error, Equatable {
        case taken
        case refused(OSStatus)
    }

    /// "BRHK". Carbon tells hot keys apart by signature and ID.
    private static let signature: OSType = 0x4252_484B

    private let identifier: EventHotKeyID
    private let action: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    /// Without a handler a registered combo would do nothing, so `register` reports this instead.
    private var handlerStatus: OSStatus = noErr

    /// The handler stays installed for the life of the app, which is also this object's life.
    /// Every handler on the application target sees every hot key press, so `id` has to be unique
    /// and a press for another ID is passed on to the next handler.
    init(id: UInt32, action: @escaping () -> Void) {
        identifier = EventHotKeyID(signature: Self.signature, id: id)
        self.action = action
        var pressed = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var pressedID = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil,
                    &pressedID)
                guard status == noErr else { return status }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // The application event target delivers on the main thread.
                return MainActor.assumeIsolated {
                    guard pressedID.signature == hotKey.identifier.signature,
                        pressedID.id == hotKey.identifier.id
                    else { return OSStatus(eventNotHandledErr) }
                    hotKey.action()
                    return noErr
                }
            },
            1, &pressed, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    /// Replaces whatever was registered. Nil just unregisters.
    func register(_ combo: KeyCombo?) throws(RegistrationError) {
        unregister()
        guard let combo else { return }
        guard handlerStatus == noErr else { throw .refused(handlerStatus) }
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode), combo.carbonModifiers, identifier,
            GetApplicationEventTarget(), 0, &hotKeyRef)
        switch status {
        case noErr: return
        case OSStatus(eventHotKeyExistsErr): throw .taken
        default: throw .refused(status)
        }
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }
}
