import AppKit
import NotepadXXCore
import NotepadXXDesign

/// Records a shortcut by capturing the key event itself.
///
/// The design's rule: "the field captures the raw key event, so a shortcut is
/// shown exactly as it will fire". Typing a letter into a text field and then
/// ticking modifier boxes can describe a shortcut the keyboard cannot produce.
/// Modifier-only presses do not commit, ⌫ clears, and Esc cancels.
final class ShortcutRecorderField: NSView {
    /// Called with the captured binding, or nil when ⌫ cleared it.
    var onCapture: ((KeyBinding?) -> Void)?
    /// Called when Esc is pressed.
    var onCancel: (() -> Void)?

    private(set) var binding: KeyBinding?
    private let label = NSTextField(labelWithString: "")

    init(binding: KeyBinding?) {
        self.binding = binding
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
        wantsLayer = true
        label.alignment = .center
        label.font = DS.Font.bodyEmphasis()
        label.textColor = DS.Color.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 28),
            widthAnchor.constraint(equalToConstant: 220),
        ])
        refresh()
        setAccessibilityRole(.textField)
        setAccessibilityLabel("Shortcut. Hold the modifiers and press a key.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

    override func draw(_ dirtyRect: NSRect) {
        DS.Color.controlFill.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DS.Radius.control, yRadius: DS.Radius.control)
        path.fill()
        (window?.firstResponder === self ? DS.Color.brand : DS.Color.controlBorder).setStroke()
        path.lineWidth = window?.firstResponder === self ? 2 : 1
        path.stroke()
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape cancels, Delete clears. Neither is a shortcut being recorded.
        if event.keyCode == 53, modifiers.isEmpty {
            onCancel?()
            return
        }
        if event.keyCode == 51, modifiers.isEmpty {
            binding = nil
            refresh()
            onCapture?(nil)
            return
        }

        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return }
        binding = KeyBinding(key: characters.lowercased(), modifiers: modifiers.rawValue)
        refresh()
        onCapture?(binding)
    }

    /// A modifier on its own is not a shortcut, so holding ⌘ shows what is held
    /// without committing anything.
    override func flagsChanged(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard binding == nil else { return }
        label.stringValue = modifiers.isEmpty
            ? "Press a shortcut"
            : KeyBinding(key: "", modifiers: modifiers.rawValue).displayString
        label.textColor = DS.Color.textSecondary
    }

    private func refresh() {
        label.stringValue = binding?.displayString ?? "Press a shortcut"
        label.textColor = binding == nil ? DS.Color.textSecondary : DS.Color.textPrimary
    }
}
