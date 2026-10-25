import Foundation

enum Options {
    static let styling = ["casual", "semi-casual", "semi-formal", "formal"]
    static let structure = ["prose", "lists"]
    static let context = ["general", "email"]
    static let whisperSizes = ["tiny.en", "base.en", "small.en", "medium.en"]
    static let idleMinutes = [0, 5, 10, 30]  // 0 = never unload
}

enum HotkeyKey: String, CaseIterable {
    case rightOption = "right_option"
    case rightCommand = "right_command"

    var label: String { self == .rightOption ? "Right Option" : "Right Command" }
    var keyCode: Int64 { self == .rightOption ? 61 : 54 }
}

enum HotkeyMode: String, CaseIterable {
    case hold, toggle

    var label: String { self == .hold ? "Hold to talk" : "Tap to start / stop" }
}

/// UserDefaults-backed settings. Imports the Python-era config.json once.
final class Settings {
    static let shared = Settings()
    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            "hotkey": HotkeyKey.rightOption.rawValue,
            "hotkeyMode": HotkeyMode.hold.rawValue,
            "whisperModel": "small.en",
            "styling": "semi-formal",
            "structure": "prose",
            "context": "general",
            "autoPaste": true,
            "idleMinutes": 10,
        ])
        importLegacyConfig()
    }

    var hotkey: HotkeyKey {
        get { HotkeyKey(rawValue: d.string(forKey: "hotkey") ?? "") ?? .rightOption }
        set { d.set(newValue.rawValue, forKey: "hotkey") }
    }
    var hotkeyMode: HotkeyMode {
        get { HotkeyMode(rawValue: d.string(forKey: "hotkeyMode") ?? "") ?? .hold }
        set { d.set(newValue.rawValue, forKey: "hotkeyMode") }
    }
    var whisperModel: String {
        get { valid(d.string(forKey: "whisperModel"), Options.whisperSizes, "small.en") }
        set { d.set(newValue, forKey: "whisperModel") }
    }
    var styling: String {
        get { valid(d.string(forKey: "styling"), Options.styling, "semi-formal") }
        set { d.set(newValue, forKey: "styling") }
    }
    var structure: String {
        get { valid(d.string(forKey: "structure"), Options.structure, "prose") }
        set { d.set(newValue, forKey: "structure") }
    }
    var context: String {
        get { valid(d.string(forKey: "context"), Options.context, "general") }
        set { d.set(newValue, forKey: "context") }
    }
    /// Input device UID; nil means system default.
    var inputDevice: String? {
        get { d.string(forKey: "inputDevice") }
        set { d.set(newValue, forKey: "inputDevice") }
    }
    var autoPaste: Bool {
        get { d.bool(forKey: "autoPaste") }
        set { d.set(newValue, forKey: "autoPaste") }
    }
    var idleMinutes: Int {
        get { d.integer(forKey: "idleMinutes") }
        set { d.set(newValue, forKey: "idleMinutes") }
    }

    private func valid(_ value: String?, _ allowed: [String], _ fallback: String) -> String {
        guard let value, allowed.contains(value) else { return fallback }
        return value
    }

    private func importLegacyConfig() {
        guard !d.bool(forKey: "legacyImported") else { return }
        d.set(true, forKey: "legacyImported")
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/simple-wisper/config.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        if let v = json["hotkey"] as? String, let key = HotkeyKey(rawValue: v) { hotkey = key }
        if let v = json["whisper_model"] as? String { whisperModel = v }
        if let v = json["styling"] as? String { styling = v }
        if let v = json["structure"] as? String { structure = v }
        if let v = json["context"] as? String { context = v }
        if let v = json["auto_paste"] as? Bool { autoPaste = v }
    }
}
