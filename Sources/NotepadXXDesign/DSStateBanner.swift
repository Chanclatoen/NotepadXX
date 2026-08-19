import AppKit

/// A panel-width banner reporting what a window is doing, or why it cannot.
///
/// The design gives these five states one shape: a glyph, a title, a sentence,
/// optionally a progress bar or a monospaced detail, and the actions that make
/// sense. Colour follows the severity, and a glyph carries it too, so the state
/// is never signalled by hue alone.
public final class DSStateBanner: NSView {
    public enum Severity {
        case working, success, warning, error

        var tint: NSColor {
            switch self {
            case .working: return DS.Color.caret
            case .success: return DS.Color.success
            case .warning: return DS.Color.warning
            case .error: return DS.Color.error
            }
        }

        var symbol: String {
            switch self {
            case .working: return "arrow.triangle.2.circlepath"
            case .success: return "checkmark.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "exclamationmark.shield"
            }
        }

        /// A tint behind the banner for the states that need to be noticed.
        var background: NSColor {
            switch self {
            case .working: return DS.Color.panel
            case .success: return DS.Color.successTint
            case .warning: return DS.Color.warningTint
            case .error: return DS.Color.errorTint
            }
        }
    }

    /// One state to show.
    public struct State {
        public let severity: Severity
        public let title: String
        public let message: String
        /// A monospaced detail, such as the two checksums that disagree.
        public let detail: String?
        /// Determinate progress, 0...1, when there is something to measure.
        public let progress: Double?
        /// Buttons, in the order they should appear.
        public let actions: [(title: String, handler: () -> Void)]

        public init(severity: Severity, title: String, message: String,
                    detail: String? = nil, progress: Double? = nil,
                    actions: [(title: String, handler: () -> Void)] = []) {
            self.severity = severity
            self.title = title
            self.message = message
            self.detail = detail
            self.progress = progress
            self.actions = actions
        }
    }

    private let glyph = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let actionRow = NSStackView()
    private var handlers: [() -> Void] = []
    private var severity: Severity = .working

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = DS.Font.bodyEmphasis()
        messageLabel.font = DS.Font.small()
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 3
        detailLabel.font = DS.Font.mono(11)
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 3

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.controlSize = .small

        actionRow.orientation = .horizontal
        actionRow.spacing = DS.Space.s

        let text = NSStackView(views: [titleLabel, messageLabel, detailLabel, progressBar, actionRow])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = DS.Space.xs

        let row = NSStackView(views: [glyph, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = DS.Space.l
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: DS.Space.l),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: DS.Space.l),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -DS.Space.l),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -DS.Space.l),
            glyph.widthAnchor.constraint(equalToConstant: 18),
            progressBar.widthAnchor.constraint(equalToConstant: 220),
        ])
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func updateLayer() {
        layer?.backgroundColor = severity.background.cgColor
        layer?.cornerRadius = DS.Radius.control
        layer?.borderWidth = 1
        layer?.borderColor = severity.tint.withAlphaComponent(0.35).cgColor
    }

    /// Shows a state, or nothing when passed nil.
    public func show(_ state: State?) {
        guard let state else {
            isHidden = true
            return
        }
        isHidden = false
        severity = state.severity
        glyph.image = DS.symbol(state.severity.symbol, pointSize: 15, color: state.severity.tint)
        titleLabel.stringValue = state.title
        titleLabel.textColor = DS.Color.textPrimary
        messageLabel.stringValue = state.message
        messageLabel.textColor = DS.Color.textSecondary

        detailLabel.stringValue = state.detail ?? ""
        detailLabel.textColor = state.severity.tint
        detailLabel.isHidden = state.detail == nil

        if let progress = state.progress {
            progressBar.isHidden = false
            progressBar.doubleValue = progress * 100
        } else {
            progressBar.isHidden = true
        }

        handlers = state.actions.map(\.handler)
        actionRow.setViews(state.actions.enumerated().map { index, action in
            let button = NSButton(title: action.title, target: self, action: #selector(actionTapped(_:)))
            button.bezelStyle = .rounded
            button.tag = index
            return button
        }, in: .leading)
        actionRow.isHidden = state.actions.isEmpty

        // The whole banner reads as one announcement rather than four fragments.
        setAccessibilityLabel("\(state.title). \(state.message)")
        needsDisplay = true
        updateLayer()
    }

    @objc private func actionTapped(_ sender: NSButton) {
        guard handlers.indices.contains(sender.tag) else { return }
        handlers[sender.tag]()
    }

    /// What the banner is announcing, for checking the state that is shown.
    public var announcement: String { accessibilityLabel() ?? "" }
}
