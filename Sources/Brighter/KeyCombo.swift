import AppKit
import Carbon.HIToolbox

/// A recorded global shortcut: one key plus modifiers, stored as the virtual key code so it
/// survives keyboard layout changes.
struct KeyCombo: Codable, Equatable {
    let keyCode: UInt16
    let modifierFlags: UInt
    /// What the key shows as in Settings, captured when it was recorded.
    let keyName: String

    /// A global shortcut fires in every app, so a bare key or Shift alone would eat ordinary
    /// typing. At least one of these has to be held.
    private static let requiredModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
    private static let keptModifiers: NSEvent.ModifierFlags = [
        .command, .option, .control, .shift,
    ]

    /// Keys whose characters are blank or private-use glyphs, so they need a name of their own.
    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑",
        kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    /// Nil when no Command, Option or Control is held, or the key has nothing to show.
    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) {
        let kept = modifiers.intersection(Self.keptModifiers)
        guard !kept.isDisjoint(with: Self.requiredModifiers) else { return nil }
        let name = Self.specialKeyNames[Int(keyCode)] ?? characters?.uppercased() ?? ""
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        self.keyCode = keyCode
        self.modifierFlags = kept.rawValue
        self.keyName = name
    }

    init?(event: NSEvent) {
        self.init(
            keyCode: event.keyCode, modifiers: event.modifierFlags,
            characters: event.charactersIgnoringModifiers)
    }

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierFlags) }

    /// In the order the system menus use: Control, Option, Shift, Command.
    var displayString: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [
            (.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"),
        ]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyName
    }

    /// The modifier mask `RegisterEventHotKey` takes.
    var carbonModifiers: UInt32 {
        let masks: [(NSEvent.ModifierFlags, Int)] = [
            (.control, controlKey), (.option, optionKey), (.shift, shiftKey), (.command, cmdKey),
        ]
        return masks.filter { modifiers.contains($0.0) }.reduce(0) { $0 | UInt32($1.1) }
    }
}
