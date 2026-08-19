import AppKit
import NotepadXXCore
import NotepadXXDesign

/// The User Defined Language editor's live preview.
///
/// It repaints as the rules are typed, so a keyword group or a comment
/// delimiter can be seen working before it is saved. A "Test" button that has
/// to be pressed hides the one thing the editor is for.
final class UDLPreviewView: NSView {
    /// The sample the preview highlights. Long enough to exercise comments,
    /// strings, numbers and folding, short enough to read at a glance.
    static let sample = """
        # sample for the preview
        server {
            listen 8080;
            root "/var/www";   # a comment
            timeout 30;
        }
        """

    private let textView = NSTextView()
    private let scrollView = NSScrollView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textView.isEditable = false
        textView.drawsBackground = true
        textView.backgroundColor = DS.Color.content
        textView.textContainerInset = NSSize(width: DS.Space.m, height: DS.Space.s)

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityLabel("Live preview of this language")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Re-highlights the sample with the rules as they stand.
    func update(with definition: LanguageDefinition, sample: String = UDLPreviewView.sample) {
        let highlighter = SyntaxHighlighter(language: definition)
        highlighter.setText(sample)

        let text = NSMutableAttributedString(
            string: sample,
            attributes: [.font: DS.Font.mono(11), .foregroundColor: DS.Color.textPrimary])
        for token in highlighter.tokens(forLines: 0...max(0, highlighter.lineCount - 1)) {
            guard NSMaxRange(token.range) <= (sample as NSString).length else { continue }
            text.addAttribute(.foregroundColor, value: Self.colour(for: token.type), range: token.range)
        }
        textView.textStorage?.setAttributedString(text)
    }

    /// What the preview is showing, so the highlighting can be checked.
    var highlighted: NSAttributedString { textView.attributedString() }

    private static func colour(for type: TokenType) -> NSColor {
        switch type {
        case .comment, .commentLine: return DS.SyntaxPalette.xcodeComment
        case .string, .character: return DS.SyntaxPalette.xcodeString
        case .number: return DS.SyntaxPalette.xcodeNumber
        case .keyword1: return DS.SyntaxPalette.xcodeKeyword
        case .keyword2: return DS.SyntaxPalette.xcodeType
        case .keyword3: return DS.SyntaxPalette.xcodeFunction
        case .keyword4: return DS.SyntaxPalette.xcodeAttribute
        case .preprocessor: return DS.SyntaxPalette.xcodeAttribute
        case .operatorToken, .delimiter: return DS.SyntaxPalette.xcodePlain
        default: return DS.SyntaxPalette.xcodePlain
        }
    }
}
