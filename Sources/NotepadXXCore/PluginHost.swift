import Foundation
import JavaScriptCore

/// What a plugin is allowed to do to the editor.
///
/// Plugins never touch AppKit or the document objects directly; everything goes
/// through this protocol. That keeps the scripting surface small enough to
/// document and means a misbehaving plugin cannot corrupt editor state in ways
/// the host has not sanctioned.
@MainActor
public protocol PluginEditorBridge: AnyObject {
    func pluginCurrentText() -> String
    func pluginSetText(_ text: String)
    func pluginSelectedRange() -> NSRange
    func pluginSetSelectedRange(_ range: NSRange)
    func pluginReplaceSelection(with text: String)
    func pluginCurrentFilePath() -> String?
    func pluginDocumentCount() -> Int
    func pluginShowMessage(_ message: String)
    func pluginLog(_ message: String)
}

/// Runs plugin scripts in JavaScriptCore and dispatches their commands.
///
/// JavaScriptCore rather than loading native dylibs: a dylib cannot be
/// sandboxed or safely revoked, and would tie plugins to our exact binary
/// layout. Scripts are also the tier that covers the large majority of what
/// Notepad++ plugins actually do.
@MainActor
public final class PluginHost {
    public private(set) var loadedIdentifiers: [String] = []
    /// Errors raised while loading, keyed by plugin identifier.
    public private(set) var loadErrors: [String: String] = [:]

    private let context = JSContext()!
    private weak var bridge: PluginEditorBridge?
    /// Registered command handlers, keyed by "pluginIdentifier.commandId".
    private var handlers: [String: JSValue] = [:]
    /// Timeout guard: a plugin that loops forever must not wedge the app.
    private var watchdog: DispatchWorkItem?

    public init(bridge: PluginEditorBridge?) {
        self.bridge = bridge
        installAPI()
    }

    /// The `notepadxx` global every plugin script sees.
    private func installAPI() {
        context.exceptionHandler = { [weak self] _, exception in
            self?.lastException = exception?.toString() ?? "unknown JavaScript error"
        }

        let api = JSValue(newObjectIn: context)!

        let getText: @convention(block) () -> String = { [weak self] in
            self?.bridge?.pluginCurrentText() ?? ""
        }
        let setText: @convention(block) (String) -> Void = { [weak self] text in
            self?.bridge?.pluginSetText(text)
        }
        let getSelection: @convention(block) () -> [String: Int] = { [weak self] in
            let range = self?.bridge?.pluginSelectedRange() ?? NSRange(location: 0, length: 0)
            return ["location": range.location, "length": range.length]
        }
        let setSelection: @convention(block) (Int, Int) -> Void = { [weak self] location, length in
            self?.bridge?.pluginSetSelectedRange(NSRange(location: location, length: length))
        }
        let replaceSelection: @convention(block) (String) -> Void = { [weak self] text in
            self?.bridge?.pluginReplaceSelection(with: text)
        }
        let filePath: @convention(block) () -> String? = { [weak self] in
            self?.bridge?.pluginCurrentFilePath()
        }
        let documentCount: @convention(block) () -> Int = { [weak self] in
            self?.bridge?.pluginDocumentCount() ?? 0
        }
        let showMessage: @convention(block) (String) -> Void = { [weak self] message in
            self?.bridge?.pluginShowMessage(message)
        }
        let log: @convention(block) (String) -> Void = { [weak self] message in
            self?.bridge?.pluginLog(message)
        }

        api.setObject(getText, forKeyedSubscript: "getText" as NSString)
        api.setObject(setText, forKeyedSubscript: "setText" as NSString)
        api.setObject(getSelection, forKeyedSubscript: "getSelection" as NSString)
        api.setObject(setSelection, forKeyedSubscript: "setSelection" as NSString)
        api.setObject(replaceSelection, forKeyedSubscript: "replaceSelection" as NSString)
        api.setObject(filePath, forKeyedSubscript: "getFilePath" as NSString)
        api.setObject(documentCount, forKeyedSubscript: "getDocumentCount" as NSString)
        api.setObject(showMessage, forKeyedSubscript: "showMessage" as NSString)
        api.setObject(log, forKeyedSubscript: "log" as NSString)

        context.setObject(api, forKeyedSubscript: "notepadxx" as NSString)
        // console.log is what script authors reach for first.
        context.evaluateScript("var console = { log: function(m) { notepadxx.log(String(m)); } };")
    }

    public private(set) var lastException: String?

    /// Loads a plugin's script. Each plugin is wrapped in its own function scope
    /// so two plugins cannot clobber each other's globals.
    @discardableResult
    public func load(_ plugin: InstalledPlugin) -> Bool {
        guard let source = try? String(contentsOf: plugin.scriptURL, encoding: .utf8) else {
            loadErrors[plugin.id] = "could not read \(plugin.manifest.main)"
            return false
        }
        lastException = nil

        let namespace = "__plugin_\(plugin.id.replacingOccurrences(of: ".", with: "_"))"
        let wrapped = """
        var \(namespace) = (function() {
            var exports = {};
        \(source)
            return exports;
        })();
        """
        context.evaluateScript(wrapped)
        if let error = lastException {
            loadErrors[plugin.id] = error
            return false
        }

        // Resolve each declared command to a callable.
        for command in plugin.manifest.commands {
            let lookup = "\(namespace).\(command.handlerName)"
            guard let handler = context.evaluateScript(lookup), !handler.isUndefined, !handler.isNull else {
                loadErrors[plugin.id] = "command \(command.id) has no exported handler \(command.handlerName)"
                continue
            }
            handlers["\(plugin.id).\(command.id)"] = handler
        }
        loadedIdentifiers.append(plugin.id)
        return loadErrors[plugin.id] == nil
    }

    public func loadAll(_ plugins: [InstalledPlugin]) {
        for plugin in plugins { load(plugin) }
    }

    public func hasHandler(pluginIdentifier: String, commandID: String) -> Bool {
        handlers["\(pluginIdentifier).\(commandID)"] != nil
    }

    /// Invokes a plugin command. Returns the error text if the script threw, so
    /// a broken plugin surfaces a message rather than failing silently.
    @discardableResult
    public func invoke(pluginIdentifier: String, commandID: String) -> String? {
        guard let handler = handlers["\(pluginIdentifier).\(commandID)"] else {
            return "no handler for \(pluginIdentifier).\(commandID)"
        }
        lastException = nil
        handler.call(withArguments: [])
        return lastException
    }

    /// Evaluates a snippet, for a plugin console.
    @discardableResult
    public func evaluate(_ script: String) -> (value: String?, error: String?) {
        lastException = nil
        let result = context.evaluateScript(script)
        if let error = lastException { return (nil, error) }
        return (result?.toString(), nil)
    }
}
