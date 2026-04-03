import ApplicationServices
import Foundation

public enum TextInjector {
    public static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let utf16 = Array(text.utf16)
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else {
            return
        }

        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
