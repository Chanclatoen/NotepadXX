import AppKit
import NotepadXXCore
import NotepadXXEditor

/// The "Opening …" bar shown while a large file is read and handed to the
/// editor, with a Cancel button.
@MainActor
public final class OpenProgressView: NSVisualEffectView {
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    var onCancel: (() -> Void)?
    /// Last fraction shown, kept so the bar never steps backwards between the
    /// reading and the loading phase.
    public private(set) var fraction = 0.0

    public init(fileName: String) {
        super.init(frame: .zero)
        material = .sheet
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        applyColours()
        label.stringValue = "Opening \(fileName)…"
        label.lineBreakMode = .byTruncatingMiddle
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 1
        bar.controlSize = .small
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        setAccessibilityIdentifier("open-progress")
        bar.setAccessibilityLabel("Opening \(fileName)")
        for view in [label, bar, cancelButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            bar.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 8),
            bar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            bar.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -10),
            cancelButton.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: 14),
            widthAnchor.constraint(equalToConstant: 380),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Solid, so the text behind the bar does not show through it.
    private func applyColours() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColours()
    }

    public func setProgress(_ value: Double) {
        fraction = max(fraction, min(1, value))
        bar.doubleValue = fraction
    }

    @objc private func cancelTapped() { onCancel?() }
}

/// Cancellation flag shared with the background read.
final class OpenToken: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func cancel() { lock.lock(); flag = true; lock.unlock() }
}

extension MainWindowController {
    /// Files at or above this size are read off the main thread with a
    /// progress bar; smaller ones open at once, as before.
    public static var backgroundOpenThreshold = 5 * 1_048_576

    /// Opens `url`, or focuses its tab, and calls `completion` with whether
    /// that worked. Small files complete before this returns. A large file is
    /// read and decoded on a background queue, shows a cancellable progress
    /// bar, and completes once its text is fully in the editor; the window
    /// keeps responding meanwhile.
    public func openOrFocusAsync(url: URL, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        if indexOfDocument(for: url) != nil { return completion(openOrFocus(url: url)) }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
        guard let size, size >= Self.backgroundOpenThreshold else { return completion(openOrFocus(url: url)) }
        let key = url.resolvingSymlinksInPath().standardizedFileURL
        if openingURLs[key] != nil { return completion(true) }

        let banner = showOpenProgress(for: url)
        openingURLs[key] = banner
        let token = OpenToken()
        banner.onCancel = { token.cancel() }

        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: Result<(TextDocument, [Int]), Error>
            do {
                let document = try TextDocument.load(
                    contentsOf: url,
                    progress: { fraction in
                        DispatchQueue.main.async { banner.setProgress(0.5 * fraction) }
                    },
                    isCancelled: { token.isCancelled })
                // The highlighter's line index is the other big pass over the
                // text; doing it here keeps it off the main thread.
                let starts = SyntaxHighlighter.computeLineStarts(document.text)
                outcome = token.isCancelled ? .failure(TextDocument.LoadError.cancelled) : .success((document, starts))
            } catch {
                outcome = .failure(error)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.openingURLs[key] = nil
                    switch outcome {
                    case .failure(let error):
                        banner.removeFromSuperview()
                        if case TextDocument.LoadError.cancelled = error { return completion(false) }
                        completion(false)
                    case .success(let (document, starts)):
                        self.finishBackgroundOpen(document, lineStarts: starts, url: url,
                                                  banner: banner, token: token, completion: completion)
                    }
                }
            }
        }
    }

    private func finishBackgroundOpen(
        _ document: TextDocument, lineStarts: [Int], url: URL,
        banner: OpenProgressView, token: OpenToken,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        // Another route may have opened the same file while this one read it.
        if let index = indexOfDocument(for: url) {
            banner.removeFromSuperview()
            selectTab(at: index)
            return completion(true)
        }
        if let limit = preferencesStore?.preferences.readOnlyAboveMegabytes, limit > 0,
           let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
           size > limit * 1_048_576 {
            document.isReadOnly = true
        }
        openingURLs[url.resolvingSymlinksInPath().standardizedFileURL] = banner
        progressiveLoads[document.id] = lineStarts
        appendDocument(document)
        noteRecentlyOpened(url)
        let editor = editorController(for: document)
        // From here Cancel means: stop feeding the editor and drop the tab.
        banner.onCancel = { [weak self, weak editor, weak document] in
            editor?.cancelLoading()
            if let self, let document, let index = self.documents.firstIndex(where: { $0 === document }) {
                self.performClose(index: index)
            }
        }
        editor.whenLoaded { [weak self] loaded in
            self?.openingURLs[url.resolvingSymlinksInPath().standardizedFileURL] = nil
            banner.removeFromSuperview()
            completion(loaded)
        }
    }

    private func showOpenProgress(for url: URL) -> OpenProgressView {
        let banner = OpenProgressView(fileName: url.lastPathComponent)
        banner.translatesAutoresizingMaskIntoConstraints = false
        if let content = window?.contentView {
            content.addSubview(banner)
            NSLayoutConstraint.activate([
                banner.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                banner.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -64),
            ])
        }
        return banner
    }
}
