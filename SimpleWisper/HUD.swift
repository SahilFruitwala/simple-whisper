import AppKit

/// Non-activating HUD capsule near the bottom of the screen. The dot colour marks the stage.
final class HUD {
    enum Stage {
        case onAir, loading, transcribing, polishing, message(String)

        var title: String {
            switch self {
            case .onAir: "ON AIR"
            case .loading: "LOADING MODELS"
            case .transcribing: "TRANSCRIBING"
            case .polishing: "POLISHING"
            case .message(let text): text
            }
        }

        var color: NSColor {
            switch self {
            case .onAir: NSColor(calibratedRed: 0.91, green: 0.64, blue: 0.09, alpha: 1)
            case .transcribing, .loading: NSColor(calibratedRed: 0.62, green: 0.78, blue: 0.84, alpha: 1)
            case .polishing: NSColor(calibratedRed: 0.91, green: 0.64, blue: 0.09, alpha: 1)
            case .message: NSColor(calibratedRed: 0.85, green: 0.35, blue: 0.30, alpha: 1)
            }
        }
    }

    private static let size = NSSize(width: 340, height: 46)
    private lazy var panel: NSPanel = makePanel()
    private let capsule = CapsuleView(frame: NSRect(origin: .zero, size: HUD.size))
    private let label = NSTextField(labelWithString: "")
    private var hideWork: DispatchWorkItem?

    func show(_ stage: Stage, autoHide: TimeInterval? = nil) {
        hideWork?.cancel()
        capsule.dot = stage.color
        capsule.needsDisplay = true
        label.stringValue = stage.title
        position()
        panel.orderFrontRegardless()
        if let autoHide {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + autoHide, execute: work)
        }
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }

    private func position() {
        let screen = NSScreen.main?.frame ?? .zero
        panel.setFrameOrigin(NSPoint(x: screen.midX - HUD.size.width / 2, y: screen.minY + 96))
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: HUD.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        let lineHeight = font.ascender - font.descender + font.leading
        label.frame = NSRect(x: 0, y: (HUD.size.height - lineHeight) / 2, width: HUD.size.width, height: lineHeight)
        label.font = font
        label.alignment = .center
        label.textColor = NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.86, alpha: 1)
        capsule.addSubview(label)
        panel.contentView = capsule
        return panel
    }
}

private final class CapsuleView: NSView {
    var dot: NSColor = .orange

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor(calibratedRed: 0.11, green: 0.10, blue: 0.08, alpha: 0.92).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        dot.setFill()
        NSBezierPath(ovalIn: NSRect(x: 14, y: (bounds.height - 8) / 2, width: 8, height: 8)).fill()
    }
}
