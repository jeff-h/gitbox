import AppKit
import WebKit

/// Built-in diff viewer — an app-modal window hosting a WKWebView that runs
/// Monaco's diff editor against the two blob files prepared by GBChange.
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
///
/// The controller is **cached** across opens: after the first close the
/// instance is kept alive in a static var, so subsequent diffs reuse the
/// already-warmed WKWebView + Monaco editor. First open: ~1 s. Subsequent:
/// ~50 ms. Costs ~150 MB resident, but only after the user has opened a
/// diff at least once, so users who never touch it pay nothing.
@objc(GBBuiltinDiffWindowController)
class GBBuiltinDiffWindowController: NSWindowController, NSWindowDelegate, WKNavigationDelegate, WKScriptMessageHandler {

    private static var cached: GBBuiltinDiffWindowController?
    private static var idleEvictTimer: Timer?
    private static let idleEvictSeconds: TimeInterval = 120
    private static let sizeDefaultsKey = "GBBuiltinDiffSheetSize"

    private var leftURL: URL = URL(fileURLWithPath: "/dev/null")
    private var rightURL: URL = URL(fileURLWithPath: "/dev/null")
    private var displayPath: String = ""
    private var webView: WKWebView!
    private var htmlLoaded = false
    private var loadPending = false

    /// Entry point called from ObjC. Reuses the cached instance if present;
    /// otherwise creates one and caches it after the modal closes.
    @objc(presentWithLeftURL:rightURL:displayPath:)
    class func present(leftURL: URL, rightURL: URL, displayPath: String) {
        idleEvictTimer?.invalidate()
        idleEvictTimer = nil

        let wc = cached ?? GBBuiltinDiffWindowController()
        cached = wc
        wc.update(leftURL: leftURL, rightURL: rightURL, displayPath: displayPath)
        wc.runModalWindow()
    }

    /// Schedule eviction of the cached instance N seconds from now, so the
    /// WKWebView + WebKit content process get reclaimed if the user doesn't
    /// open another diff. Reset on every present().
    private static func scheduleIdleEviction() {
        idleEvictTimer?.invalidate()
        idleEvictTimer = Timer.scheduledTimer(withTimeInterval: idleEvictSeconds, repeats: false) { _ in
            cached?.tearDownForEviction()
            cached = nil
            idleEvictTimer = nil
        }
    }

    /// Break the retain cycle through WKUserContentController (which strongly
    /// retains its message handlers, i.e. self) so ARC can actually free
    /// everything when `cached` drops its reference.
    private func tearDownForEviction() {
        window?.orderOut(nil)
        let userContent = webView?.configuration.userContentController
        userContent?.removeScriptMessageHandler(forName: "gbReadOnlyBeep")
        userContent?.removeScriptMessageHandler(forName: "gbCloseSheet")
        webView?.navigationDelegate = nil
        window?.delegate = nil
    }

    private init() {
        let savedSize = Self.loadSavedSize() ?? NSSize(width: 1100, height: 720)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: savedSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
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

        let done = NSButton(title: "Done", target: self, action: #selector(closeWindow(_:)))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        done.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(done)

        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            web.topAnchor.constraint(equalTo: container.topAnchor),
            web.bottomAnchor.constraint(equalTo: done.topAnchor, constant: -20),
            done.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            done.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])

        userContent.add(self, name: "gbReadOnlyBeep")
        userContent.add(self, name: "gbCloseSheet")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private func update(leftURL: URL, rightURL: URL, displayPath: String) {
        self.leftURL = leftURL
        self.rightURL = rightURL
        self.displayPath = displayPath
        window?.title = (displayPath as NSString).lastPathComponent
    }

    private func runModalWindow() {
        guard let window = self.window else { return }
        if !htmlLoaded {
            guard let monacoDir = Bundle.main.url(forResource: "MonacoDiff", withExtension: nil),
                  let htmlURL = Bundle.main.url(forResource: "diff", withExtension: "html",
                                                subdirectory: "MonacoDiff") else {
                NSLog("GBBuiltinDiffWindowController: MonacoDiff resources not found in bundle")
                return
            }
            loadPending = true
            webView.loadFileURL(htmlURL, allowingReadAccessTo: monacoDir)
        } else {
            // Reuse warm webview: just re-invoke __gbLoadDiff with new content.
            pushDiffToWebView()
        }
        window.center()
        NSApp.runModal(for: window)
    }

    @objc private func closeWindow(_ sender: Any?) {
        guard let window = self.window else { return }
        Self.saveSize(window.frame.size)
        NSApp.stopModal()
        window.orderOut(nil)
        // Keep instance warm for fast subsequent opens; evict after idle timeout.
        Self.scheduleIdleEviction()
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
        closeWindow(sender)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeWindow(nil)
        return false
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        htmlLoaded = true
        if loadPending {
            loadPending = false
            pushDiffToWebView()
        }
    }

    private func pushDiffToWebView() {
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
            closeWindow(nil)
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
