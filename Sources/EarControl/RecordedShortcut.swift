import AppKit
import CoreGraphics
import Foundation

struct RecordedShortcut: Codable, Equatable {
    enum Kind: String, Codable {
        case key
        case modifier
    }

    let keyCode: UInt16
    let modifierFlagsRawValue: UInt
    let kind: Kind

    static func key(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> RecordedShortcut {
        RecordedShortcut(
            keyCode: keyCode,
            modifierFlagsRawValue: normalized(modifiers).rawValue,
            kind: .key
        )
    }

    static func modifier(keyCode: UInt16) -> RecordedShortcut? {
        guard modifierDescriptor(for: keyCode) != nil else { return nil }
        return RecordedShortcut(keyCode: keyCode, modifierFlagsRawValue: 0, kind: .modifier)
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    var cgFlags: CGEventFlags {
        CGEventFlags(rawValue: UInt64(modifierFlagsRawValue))
    }

    var displayTitle: String {
        if kind == .modifier {
            return Self.modifierDescriptor(for: keyCode)?.title ?? "未知修饰键"
        }
        return Self.modifierSymbols(modifierFlags) + Self.keyName(for: keyCode)
    }

    var compactTitle: String { displayTitle }

    var bareModifierFlags: CGEventFlags? {
        guard kind == .modifier, let descriptor = Self.modifierDescriptor(for: keyCode) else { return nil }
        return descriptor.genericFlag
    }

    var bareModifierDeviceFlag: CGEventFlags? {
        guard kind == .modifier, let descriptor = Self.modifierDescriptor(for: keyCode) else { return nil }
        return descriptor.deviceFlag
    }

    static func normalized(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift])
    }

    static func isSupportedModifierKeyCode(_ keyCode: UInt16) -> Bool {
        modifierDescriptor(for: keyCode) != nil
    }

    static func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags? {
        switch keyCode {
        case 54, 55: .command
        case 56, 60: .shift
        case 58, 61: .option
        case 59, 62: .control
        default: nil
        }
    }

    private struct ModifierDescriptor {
        let title: String
        let genericFlag: CGEventFlags
        let deviceFlag: CGEventFlags
    }

    private static func modifierDescriptor(for keyCode: UInt16) -> ModifierDescriptor? {
        switch keyCode {
        case 55: ModifierDescriptor(title: "左 Command", genericFlag: .maskCommand, deviceFlag: CGEventFlags(rawValue: 0x08))
        case 54: ModifierDescriptor(title: "右 Command", genericFlag: .maskCommand, deviceFlag: CGEventFlags(rawValue: 0x10))
        case 56: ModifierDescriptor(title: "左 Shift", genericFlag: .maskShift, deviceFlag: CGEventFlags(rawValue: 0x02))
        case 60: ModifierDescriptor(title: "右 Shift", genericFlag: .maskShift, deviceFlag: CGEventFlags(rawValue: 0x04))
        case 58: ModifierDescriptor(title: "左 Option", genericFlag: .maskAlternate, deviceFlag: CGEventFlags(rawValue: 0x20))
        case 61: ModifierDescriptor(title: "右 Option", genericFlag: .maskAlternate, deviceFlag: CGEventFlags(rawValue: 0x40))
        case 59: ModifierDescriptor(title: "左 Control", genericFlag: .maskControl, deviceFlag: CGEventFlags(rawValue: 0x01))
        case 62: ModifierDescriptor(title: "右 Control", genericFlag: .maskControl, deviceFlag: CGEventFlags(rawValue: 0x2000))
        default: nil
        }
    }

    private static func modifierSymbols(_ flags: NSEvent.ModifierFlags) -> String {
        var value = ""
        if flags.contains(.control) { value += "⌃" }
        if flags.contains(.option) { value += "⌥" }
        if flags.contains(.shift) { value += "⇧" }
        if flags.contains(.command) { value += "⌘" }
        return value
    }

    private static func keyName(for keyCode: UInt16) -> String {
        keyNames[keyCode] ?? "Key (keyCode)"
    }

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3",
        21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]",
        31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Escape", 65: "Num .", 67: "Num *", 69: "Num +", 75: "Num /",
        76: "Enter", 78: "Num -", 81: "Num =", 82: "Num 0", 83: "Num 1", 84: "Num 2", 85: "Num 3",
        86: "Num 4", 87: "Num 5", 88: "Num 6", 89: "Num 7", 91: "Num 8", 92: "Num 9",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13",
        106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 115: "Home", 116: "Page Up",
        117: "Forward Delete", 118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

struct MiddleGestureAction: Codable, Equatable {
    enum Kind: String, Codable {
        case shortcut
        case selectAllAndDelete
        case finishVoiceAndSend
    }

    let kind: Kind
    let recordedShortcut: RecordedShortcut?

    static func shortcut(_ shortcut: RecordedShortcut) -> MiddleGestureAction {
        MiddleGestureAction(kind: .shortcut, recordedShortcut: shortcut)
    }

    static let selectAllAndDelete = MiddleGestureAction(
        kind: .selectAllAndDelete,
        recordedShortcut: nil
    )

    static let finishVoiceAndSend = MiddleGestureAction(
        kind: .finishVoiceAndSend,
        recordedShortcut: nil
    )

    var displayTitle: String {
        switch kind {
        case .shortcut: recordedShortcut?.displayTitle ?? "未知快捷键"
        case .selectAllAndDelete: "全选并删除"
        case .finishVoiceAndSend: "结束语音并发送"
        }
    }

    var compactTitle: String { displayTitle }
}

struct MiddleGestureMappings: Codable, Equatable {
    var single: MiddleGestureAction?
    var double: MiddleGestureAction?
    var triple: MiddleGestureAction?

    static let defaults = MiddleGestureMappings(single: nil, double: nil, triple: nil)

    subscript(_ gesture: MiddleGesture) -> MiddleGestureAction? {
        get {
            switch gesture {
            case .single: single
            case .double: double
            case .triple: triple
            }
        }
        set {
            switch gesture {
            case .single: single = newValue
            case .double: double = newValue
            case .triple: triple = newValue
            }
        }
    }

    var compactSummary: String {
        MiddleGesture.allCases.map { gesture in
            "\(gesture.compactTitle) \(self[gesture]?.compactTitle ?? "—")"
        }.joined(separator: " · ")
    }
}

enum MiddleGestureMappingsStore {
    static let defaultsKey = "middleGestureMappingsV2"
    static let legacyDefaultsKey = "middleGestureMappingsV1"

    static func load(from defaults: UserDefaults = .standard) -> MiddleGestureMappings {
        if let data = defaults.data(forKey: defaultsKey),
           let mappings = try? JSONDecoder().decode(MiddleGestureMappings.self, from: data) {
            return mappings
        }

        guard let legacyData = defaults.data(forKey: legacyDefaultsKey),
              let legacyMappings = try? JSONDecoder().decode(LegacyMiddleGestureMappings.self, from: legacyData)
        else { return .defaults }

        let migrated = MiddleGestureMappings(
            single: legacyMappings.single.map(MiddleGestureAction.shortcut),
            double: legacyMappings.double.map(MiddleGestureAction.shortcut),
            triple: legacyMappings.triple.map(MiddleGestureAction.shortcut)
        )
        save(migrated, to: defaults)
        return migrated
    }

    static func save(_ mappings: MiddleGestureMappings, to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(mappings) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

private struct LegacyMiddleGestureMappings: Codable {
    let single: RecordedShortcut?
    let double: RecordedShortcut?
    let triple: RecordedShortcut?
}
