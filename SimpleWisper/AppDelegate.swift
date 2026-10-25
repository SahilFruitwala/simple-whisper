import AppKit
import ApplicationServices
import AVFoundation
import ServiceManagement

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        // `Simple Wisper --selftest <audio file>` runs the model pipeline headlessly and prints timings.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count {
            SelfTest.run(path: args[i + 1])
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let settings = Settings.shared
    private let hotkey = HotkeyMonitor()
    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private let normalizer = Normalizer()
    private let hud = HUD()
    private var statusItem: NSStatusItem!
    private var busy = false
    private var lastText = ""
    private var idleTimer: Timer?
    private var warmTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setIcon(recording: false)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        log.info("Launched; accessibility trusted: \(AXIsProcessTrusted())")
        hotkey.onBegin = { [weak self] in self?.beginDictation() }
        hotkey.onEnd = { [weak self] in self?.endDictation() }
        restartHotkey()
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        checkAccessibility(prompt: true)
    }

    /// Pasting needs Accessibility, which is separate from the Input Monitoring the hotkey uses.
    /// Ask at launch, flag the menu-bar icon while it's missing, and poll until it's granted.
    private func checkAccessibility(prompt: Bool) {
        if AXIsProcessTrusted() {
            setIcon(recording: recorder.isRecording)
            return
        }
        if prompt {
            log.info("Accessibility missing; prompting")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        setIcon(recording: recorder.isRecording)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.checkAccessibility(prompt: false)
        }
    }

    // MARK: - Dictation

    private func beginDictation() {
        log.info("Hotkey down (busy: \(self.busy))")
        guard !busy, !recorder.isRecording else { return }
        do {
            try recorder.start(deviceUID: settings.inputDevice)
        } catch {
            hud.show(.message("MIC UNAVAILABLE"), autoHide: 2)
            return
        }
        idleTimer?.invalidate()
        setIcon(recording: true)
        hud.show(.onAir)
        // Load models while the user speaks so release-to-text stays fast.
        warmTask = Task { [transcriber, normalizer, settings] in
            do {
                let t0 = Date()
                try await transcriber.load(size: settings.whisperModel)
                log.info("Whisper loaded in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
                let t1 = Date()
                try await normalizer.load()
                log.info("S1-mini loaded in \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")
            } catch {
                log.error("Model load failed: \(String(describing: error))")
            }
        }
    }

    private func endDictation() {
        guard recorder.isRecording else { return }
        let audio = recorder.stop()
        log.info("Captured \(String(format: "%.2f", Double(audio.count) / Recorder.sampleRate))s of audio")
        setIcon(recording: false)
        busy = true
        let warm = warmTask
        let size = settings.whisperModel
        let (styling, structure, context) = (settings.styling, settings.structure, settings.context)

        Task { @MainActor in
            defer {
                busy = false
                scheduleUnload()
            }
            do {
                let asrReady = await transcriber.isLoaded
                let llmReady = await normalizer.isLoaded
                if !(asrReady && llmReady) { hud.show(.loading) }
                await warm?.value
                hud.show(.transcribing)
                let raw = try await transcriber.transcribe(audio, size: size)
                log.info("Whisper: \(raw)")
                guard !raw.isEmpty else { hud.hide(); return }
                hud.show(.polishing)
                let text = try await normalizer.normalize(raw, styling: styling, structure: structure, context: context)
                hud.hide()
                log.info("S1-mini: \(text)")
                guard !text.isEmpty else { return }
                lastText = text
                if !settings.autoPaste {
                    Paster.copy(text)
                } else if AXIsProcessTrusted() {
                    log.info("Pasting")
                    Paster.paste(text)
                } else {
                    // Can't send ⌘V without Accessibility; keep the text on the clipboard and say so.
                    log.error("Accessibility not granted; copied instead of pasting")
                    Paster.copy(text)
                    hud.show(.message("COPIED · ENABLE ACCESSIBILITY TO PASTE"), autoHide: 3)
                    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                    AXIsProcessTrustedWithOptions(options)
                }
            } catch {
                log.error("Dictation failed: \(String(describing: error))")
                hud.show(.message("FAILED"), autoHide: 2)
            }
        }
    }

    private func scheduleUnload() {
        idleTimer?.invalidate()
        let minutes = settings.idleMinutes
        guard minutes > 0 else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) {
            [transcriber, normalizer] _ in
            Task {
                await transcriber.unload()
                await normalizer.unload()
            }
        }
    }

    private func restartHotkey() {
        hotkey.key = settings.hotkey
        hotkey.mode = settings.hotkeyMode
        if !hotkey.start() {
            // No Accessibility/Input Monitoring yet; ask once and retry shortly.
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.restartHotkey() }
        }
    }

    private func setIcon(recording: Bool) {
        // Idle: the app's own dot + waveform glyph. Recording: a filled SF Symbol so the state is obvious.
        // Missing Accessibility: a warning glyph so it's clear auto-paste won't work.
        let image = recording
            ? NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Simple Wisper — recording")
            : AXIsProcessTrusted() || !settings.autoPaste
                ? NSImage(named: "MenuBarIcon")
                : NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Simple Wisper — needs Accessibility")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let status = AXIsProcessTrusted()
            ? "\(settings.hotkeyMode == .hold ? "Hold" : "Tap") \(settings.hotkey.label) to dictate"
            : "⚠︎ Grant Accessibility to Auto-paste…"
        let header = NSMenuItem(title: status, action: AXIsProcessTrusted() ? nil : #selector(openAccessibility), keyEquivalent: "")
        header.target = self
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(item("Copy Last", #selector(copyLast), enabled: !lastText.isEmpty))
        menu.addItem(item("Auto-paste", #selector(toggleAutoPaste), checked: settings.autoPaste))
        menu.addItem(.separator())

        menu.addItem(submenu("Styling", Options.styling, settings.styling) { self.settings.styling = $0 })
        menu.addItem(submenu("Structure", Options.structure, settings.structure) { self.settings.structure = $0 })
        menu.addItem(submenu("Context", Options.context, settings.context) { self.settings.context = $0 })
        menu.addItem(submenu("Whisper", Options.whisperSizes, settings.whisperModel) { size in
            self.settings.whisperModel = size
            Task { await self.transcriber.unload() }
        })

        let devices = Recorder.inputDevices()
        let inputNames = ["System Default"] + devices.map(\.name)
        let current = devices.first { $0.uid == settings.inputDevice }?.name ?? "System Default"
        menu.addItem(submenu("Input", inputNames, current) { name in
            self.settings.inputDevice = devices.first { $0.name == name }?.uid
        })

        let hotkeyMenu = NSMenu()
        for key in HotkeyKey.allCases {
            hotkeyMenu.addItem(closureItem(key.label, checked: settings.hotkey == key) {
                self.settings.hotkey = key
                self.restartHotkey()
            })
        }
        hotkeyMenu.addItem(.separator())
        for mode in HotkeyMode.allCases {
            hotkeyMenu.addItem(closureItem(mode.label, checked: settings.hotkeyMode == mode) {
                self.settings.hotkeyMode = mode
                self.restartHotkey()
            })
        }
        let hotkeyItem = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        hotkeyItem.submenu = hotkeyMenu
        menu.addItem(hotkeyItem)

        let labels = Options.idleMinutes.map { $0 == 0 ? "Never" : "After \($0) min" }
        let currentIdle = settings.idleMinutes == 0 ? "Never" : "After \(settings.idleMinutes) min"
        menu.addItem(submenu("Unload Models", labels, currentIdle) { label in
            let index = labels.firstIndex(of: label) ?? 2
            self.settings.idleMinutes = Options.idleMinutes[index]
            if !self.busy { self.scheduleUnload() }
        })

        menu.addItem(.separator())
        menu.addItem(item("Open at Login", #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled))
        menu.addItem(item("Quit Simple Wisper", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, enabled: Bool = true, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: key)
        item.target = self
        item.state = checked ? .on : .off
        return item
    }

    private func submenu(_ title: String, _ values: [String], _ current: String, _ pick: @escaping (String) -> Void) -> NSMenuItem {
        let sub = NSMenu()
        for value in values {
            sub.addItem(closureItem(value, checked: value == current) { pick(value) })
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = sub
        return item
    }

    private func closureItem(_ title: String, checked: Bool, _ action: @escaping () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: action)
        item.state = checked ? .on : .off
        return item
    }

    @objc private func copyLast() { Paster.copy(lastText) }
    @objc private func toggleAutoPaste() {
        settings.autoPaste.toggle()
        setIcon(recording: false)
    }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log.error("Login item change failed: \(String(describing: error))")
        }
    }
}

private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { handler() }
}
