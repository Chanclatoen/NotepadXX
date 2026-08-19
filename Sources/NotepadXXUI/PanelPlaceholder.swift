import AppKit
import NotepadXXDesign

/// The empty and loading states every panel ships with.
///
/// A panel with nothing in it should say why and what to do about it, rather
/// than showing an empty list that looks broken. The placeholder is centred
/// over the panel's own content and hides it while shown.
@MainActor
enum PanelPlaceholder {
    /// Installs a placeholder over `content` inside `container`.
    @discardableResult
    static func install(in container: NSView, over content: NSView,
                        symbol: String, title: String, message: String,
                        actionTitle: String? = nil,
                        action: (() -> Void)? = nil) -> DSEmptyState {
        let placeholder = DSEmptyState(symbol: symbol, title: title, message: message,
                                       actionTitle: actionTitle, action: action)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        placeholder.isHidden = true
        container.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            placeholder.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor,
                                                 constant: DS.Space.m),
            placeholder.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor,
                                                  constant: -DS.Space.m),
        ])
        return placeholder
    }

    /// Shows the placeholder or the content, never both.
    static func show(_ placeholder: DSEmptyState?, whenEmpty isEmpty: Bool, hiding content: NSView) {
        placeholder?.isHidden = !isEmpty
        content.isHidden = isEmpty
    }
}
