import AppKit
import CoreGraphics

/// Watches a right-side modifier via a listen-only CGEventTap.
/// Hold mode: press begins, release ends. Toggle mode: each tap flips state.
/// A modifier used as part of a chord (e.g. Right Option+E) is ignored.
final class HotkeyMonitor {
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var down = false
    private var chorded = false
    private var active = false

    var key: HotkeyKey = .rightOption
    var mode: HotkeyMode = .hold

    @discardableResult
    func start() -> Bool {
        stop()
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<HotkeyMonitor>.fromOpaque(refcon!).takeUnretainedValue()
            me.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(mask), callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        down = false
        active = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .keyDown:
            if down { chorded = true }
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == key.keyCode else { return }
            let flag: CGEventFlags = key == .rightOption ? .maskAlternate : .maskCommand
            let pressed = event.flags.contains(flag)
            if pressed && !down {
                down = true
                chorded = false
                if mode == .hold { begin() }
            } else if !pressed && down {
                down = false
                switch mode {
                case .hold:
                    // A chord means the user was typing a shortcut, not dictating.
                    end()
                case .toggle:
                    if chorded { return }
                    active ? end() : begin()
                }
            }
        default:
            break
        }
    }

    private func begin() {
        guard !active else { return }
        active = true
        onBegin()
    }

    private func end() {
        guard active else { return }
        active = false
        onEnd()
    }
}
