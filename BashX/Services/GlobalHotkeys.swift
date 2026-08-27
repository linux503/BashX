import AppKit
import Carbon

/// Global shortcuts (ClashX-style): ⌃⌘P toggle system proxy, ⌃⌘M cycle Rule→Global→Direct.
@MainActor
final class GlobalHotkeys {
    static let shared = GlobalHotkeys()

    private weak var state: AppState?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var handlerRef: EventHandlerRef?

    private enum Action: UInt32 {
        case toggleProxy = 1
        case cycleMode = 2
    }

    func install(state: AppState) {
        self.state = state
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard err == noErr else { return err }
            let service = Unmanaged<GlobalHotkeys>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                await service.handle(actionID: hotKeyID.id)
            }
            return noErr
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &handlerRef)

        register(key: UInt32(kVK_ANSI_P), modifiers: UInt32(controlKey | cmdKey), id: Action.toggleProxy.rawValue)
        register(key: UInt32(kVK_ANSI_M), modifiers: UInt32(controlKey | cmdKey), id: Action.cycleMode.rawValue)
    }

    func unregister() {
        for ref in hotKeyRefs {
            if let ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    private func register(key: UInt32, modifiers: UInt32, id: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x42485358), id: id)
        RegisterEventHotKey(key, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        hotKeyRefs.append(ref)
    }

    private func handle(actionID: UInt32) async {
        guard let state else { return }
        switch actionID {
        case Action.toggleProxy.rawValue:
            await state.setSystemProxy(!state.systemProxyOn)
        case Action.cycleMode.rawValue:
            await state.cycleProxyMode()
        default:
            break
        }
    }
}
