import AppKit
import WebKit

/// Built-in diff viewer — a sheet hosting a WKWebView that runs Monaco's
/// diff editor against the two blob files prepared by GBChange.
///
/// Enabled by selecting "Built-in" in Preferences → Integration. Everything
/// is self-contained in this file plus a small branch in
/// -[GBChange launchDiffWithBlock:] — to remove the feature, delete this
/// file, the "Built-in" entry in +[GBChange diffTools] and the matching
/// radio cell in GBPreferencesDiffViewController.xib, the branch in
/// launchDiffWithBlock:, the pbxproj entries for this file and the
/// MonacoDiff resource folder, the Fetch Monaco build phase, the
/// scripts/fetch-monaco.sh script, and the Resources/MonacoDiff directory.
///
/// Monaco is bundled inside the .app at Resources/MonacoDiff/.
@objc(GBBuiltinDiffWindowController)
class GBBuiltinDiffWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {

    // Keep a strong reference for the lifetime of the sheet — the caller
    // (GBChange) does not retain us, and beginSheet does not either.
    private static var openControllers = Set<GBBuiltinDiffWindowController>()

    private let leftURL: URL
    private let rightURL: URL
    private let displayPath: String
    private var webView: WKWebView!

    private static let sizeDefaultsKey = "GBBuiltinDiffSheetSize"

    @objc init(leftURL: URL, rightURL: URL, displayPath: String) {
        self.leftURL = leftURL
        self.rightURL = rightURL
        self.displayPath = displayPath

        let savedSize = Self.loadSavedSize() ?? NSSize(width: 1100, height: 720)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: savedSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = (displayPath as NSString).lastPathComponent
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let container = window.contentView!

        let userContent = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = userContent

        let web = WKWebView(frame: .zero, configuration: config)
        web.translatesAutoresizingMaskIntoConstraints = false
        web.navigationDelegate = self
        container.addSubview(web)
        self.webView = web

        // "Done" button — sheets have no close button. Return triggers it.
        let done = NSButton(title: "Done", target: self, action: #selector(closeSheet(_:)))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(done)

        // Esc-to-close is handled by a capture-phase keydown listener in
        // diff.html that posts gbCloseSheet — the WKWebView swallows the key
        // before it can reach NSButton's keyEquivalent or -cancelOperation:.

        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: done.topAnchor, constant: -20),
            done.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            done.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])

        // Register *after* super.init so `self` is available.
        userContent.add(self, name: "gbReadOnlyBeep")
        userContent.add(self, name: "gbCloseSheet")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// Present as a sheet on the given parent window (typically the main
    /// repository window). Blocks the calling thread until dismissed so the
    /// existing launchDiffWithBlock: contract — fire the completion block
    /// after the diff window closes — still holds.
    @objc(runModalSheetOver:)
    func runModalSheet(over parentWindow: NSWindow?) {
        guard let window = self.window else { return }
        guard let monacoDir = Bundle.main.url(forResource: "MonacoDiff", withExtension: nil),
              let htmlURL = Bundle.main.url(forResource: "diff", withExtension: "html",
                                            subdirectory: "MonacoDiff") else {
            NSLog("GBBuiltinDiffWindowController: MonacoDiff resources not found in bundle")
            return
        }
        webView.loadFileURL(htmlURL, allowingReadAccessTo: monacoDir)
        GBBuiltinDiffWindowController.openControllers.insert(self)
        _ = parentWindow // reserved for future sheet mode; ignored in window mode
        window.center()
        NSApp.runModal(for: window)
        GBBuiltinDiffWindowController.openControllers.remove(self)
    }

    @objc private func closeSheet(_ sender: Any?) {
        guard let window = self.window else { return }
        Self.saveSize(window.frame.size)
        NSApp.stopModal()
        window.orderOut(nil)
    }

    private static func loadSavedSize() -> NSSize? {
        let d = UserDefaults.standard.dictionary(forKey: sizeDefaultsKey) as? [String: CGFloat]
        guard let w = d?["w"], let h = d?["h"], w > 100, h > 100 else { return nil }
        return NSSize(width: w, height: h)
    }

    private static func saveSize(_ size: NSSize) {
        UserDefaults.standard.set(["w": size.width, "h": size.height], forKey: sizeDefaultsKey)
    }

    override func cancelOperation(_ sender: Any?) {
        closeSheet(sender)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeSheet(nil)
        return false
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let left = (try? String(contentsOf: leftURL, encoding: .utf8)) ?? ""
        let right = (try? String(contentsOf: rightURL, encoding: .utf8)) ?? ""
        let language = Self.monacoLanguage(forPath: displayPath)
        let isDark = (window?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let payload: [String: Any] = [
            "left": left,
            "right": right,
            "language": language,
            "path": displayPath,
            "theme": isDark ? "vs-dark" : "vs",
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__gbLoadDiff(\(json));", completionHandler: nil)
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "gbReadOnlyBeep" {
            NSSound.beep()
        } else if message.name == "gbCloseSheet" {
            closeSheet(nil)
        }
    }

    // MARK: - Language detection

    private static func monacoLanguage(forPath path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "m", "mm", "h": return "objective-c"
        case "c", "cc", "cpp", "cxx", "hpp", "hxx": return "cpp"
        case "js", "mjs", "cjs": return "javascript"
        case "ts", "tsx": return "typescript"
        case "jsx": return "javascript"
        case "json": return "json"
        case "html", "htm": return "html"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "less": return "less"
        case "md", "markdown": return "markdown"
        case "py": return "python"
        case "rb": return "ruby"
        case "go": return "go"
        case "rs": return "rust"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "sh", "bash", "zsh": return "shell"
        case "yml", "yaml": return "yaml"
        case "xml", "plist", "xib", "storyboard": return "xml"
        case "sql": return "sql"
        case "php": return "php"
        default: return "plaintext"
        }
    }
}
