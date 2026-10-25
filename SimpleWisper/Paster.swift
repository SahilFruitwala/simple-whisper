import AppKit

enum Paster {
    static func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Pastes `text` with a synthetic Cmd+V, then restores the previous clipboard.
    static func paste(_ text: String) {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        copy(text)
        let changeCount = pb.changeCount

        // Full Command-down, V, Command-up sequence from a private source, so modifiers the user
        // is still physically releasing (e.g. Right Option) don't leak into the shortcut.
        let source = CGEventSource(stateID: .privateState)
        let cmd: CGKeyCode = 55, v: CGKeyCode = 9
        for (key, isDown) in [(cmd, true), (v, true), (v, false), (cmd, false)] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: isDown)
            event?.flags = (key == v || isDown) ? .maskCommand : []
            event?.post(tap: .cghidEventTap)
            usleep(8_000)
        }

        // Give the target app time to read the pasteboard before restoring it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard pb.changeCount == changeCount else { return }  // something else wrote meanwhile
            restore(pb, saved)
        }
    }

    private static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { entry[type] = item.data(forType: type) }
            return entry
        }
    }

    private static func restore(_ pb: NSPasteboard, _ items: [[NSPasteboard.PasteboardType: Data]]) {
        pb.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { entry -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in entry { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(restored)
    }
}
