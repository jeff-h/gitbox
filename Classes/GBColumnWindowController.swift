import AppKit
import os.log

private let log = OSLog(subsystem: "com.oleganza.gitbox", category: "ColumnWindow")

/// Modern NSSplitViewController-based window controller that replaces the
/// XIB-based NSSplitView in GBMainWindowController with a proper
/// NSSplitViewController. The sidebar gets `.sidebar` behaviour, giving
/// us full-height sidebar under a transparent titlebar — NNW-style.
///
/// Uses the same XIB as the superclass (to inherit the toolbar definition)
/// but replaces the window's content with an NSSplitViewController.
@objc(GBColumnWindowController) class GBColumnWindowController: GBMainWindowController {

    private let splitVC = NSSplitViewController()
    private var contentContainer: NSViewController!

    /// Subview inside contentContainer that sits below the toolbar.
    /// Detail views are loaded into this view instead of the full container,
    /// so they don't render behind the toolbar.
    private var contentInsetView: NSView!

    // MARK: - Required initialisers

    override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Window lifecycle

    override func windowDidLoad() {
        os_log("windowDidLoad START", log: log, type: .default)

        // We intentionally do NOT call super. The superclass windowDidLoad
        // sets up the old XIB-based split view (loadInView:, etc.) which
        // we're replacing entirely. We replicate the essential parts here.

        guard let window = window else { return }

        // --- Modern window styling ---
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.collectionBehavior.insert(.fullScreenPrimary)

        // --- Build NSSplitViewController ---

        // Column 0: Sidebar (wraps existing GBSidebarController)
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.minimumThickness = 120
        sidebarItem.maximumThickness = 500
        sidebarItem.canCollapse = true

        // Column 1: Content container (detail views get loadInView:'d here)
        contentContainer = NSViewController()
        contentContainer.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        contentContainer.view.autoresizingMask = [.width, .height]
        let contentItem = NSSplitViewItem(viewController: contentContainer)
        contentItem.minimumThickness = 500  // cols 2+3 combined

        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(contentItem)

        // Create an inset view inside the content container that respects
        // the safe area. The top safe area inset matches the toolbar height,
        // so detail views won't render behind it.
        contentInsetView = NSView()
        contentInsetView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.view.addSubview(contentInsetView)
        NSLayoutConstraint.activate([
            contentInsetView.topAnchor.constraint(equalTo: contentContainer.view.safeAreaLayoutGuide.topAnchor),
            contentInsetView.leadingAnchor.constraint(equalTo: contentContainer.view.leadingAnchor),
            contentInsetView.trailingAnchor.constraint(equalTo: contentContainer.view.trailingAnchor),
            contentInsetView.bottomAnchor.constraint(equalTo: contentContainer.view.bottomAnchor),
        ])

        // Replace the XIB content (NSBox + old NSSplitView) with our
        // NSSplitViewController. The toolbar is window-level so it survives.
        window.contentViewController = splitVC

        // Point the inherited splitView property at the new split view.
        // This is critical: the superclass's private `sidebarView` and
        // `detailView` methods return splitView.subviews[0] and [1],
        // so setDetailViewController: will load views into the right place.
        self.splitView = splitVC.splitView


        // --- Replicate essential setup from super's windowDidLoad ---

        window.title = NSLocalizedString("No selection", comment: "Window")
        window.representedURL = nil

        sidebarController.rootController = rootController

        // Let the system sidebar visual effect show through instead of
        // the XIB's explicit _sourceListBackgroundColor.
        sidebarController.outlineView.backgroundColor = .clear

        window.initialFirstResponder = sidebarController.outlineView
        window.makeFirstResponder(sidebarController.outlineView)

        // Trigger initial selection — this sets up toolbar + detail via
        // the setSelectedWindowItem: setter in the superclass.
        self.selectedWindowItem = rootController?.selectedObject

        // Safety fallbacks (setSelectedWindowItem: handles nil, but belt and braces)
        if toolbarController == nil {
            self.toolbarController = defaultToolbarController
        }
        if detailViewController == nil {
            self.detailViewController = defaultDetailViewController
        }

        updateToolbarAlignment()
        os_log("windowDidLoad END", log: log, type: .default)
    }

    // MARK: - Toolbar alignment

    // The superclass's updateToolbarAlignment reads the sidebar width from
    // splitView.subviews[0] and sets a GBSidebarPadding toolbar item to
    // match. With NSSplitViewController, subviews[0] is an internal wrapper,
    // not the sidebar view, so the padding calculation is wrong and pushes
    // toolbar items off-screen. Disable it — proper tracking separators
    // will replace this in Step 5.
    override func updateToolbarAlignment() {
        // No-op: skip the sidebar padding hack entirely.
        // The toolbar items will start from the left edge for now.
    }

    // MARK: - Detail view management

    // The superclass's setDetailViewController: calls
    //   [detailViewController loadInView:[self detailView]]
    // where detailView returns splitView.subviews[1]. But with
    // NSSplitViewController, subviews includes internal wrappers and
    // dividers, so subviews[1] is a NSSplitDividerView — wrong!
    //
    // We override the setter to bypass that entirely and load directly
    // into our content container's view.
    override var detailViewController: NSViewController! {
        get { super.detailViewController }
        set {
            let oldVC = super.detailViewController
            oldVC?.unloadView()

            // Set the ivar via super, but skip its loadInView call by
            // temporarily nil-ing splitView so [self detailView] returns nil
            // (which makes loadInView: a no-op).
            let savedSplitView = self.splitView
            self.splitView = nil
            super.detailViewController = newValue
            self.splitView = savedSplitView

            // Now load into the inset container (below the toolbar).
            // Force layout first so contentInsetView has real bounds —
            // otherwise loadInView: sets the frame to {0,0,0,0} and
            // scroll views inside the detail view show scrollbars.
            if let vc = newValue {
                contentInsetView.superview?.layoutSubtreeIfNeeded()
                vc.load(in: contentInsetView)
                vc.view.autoresizingMask = [.width, .height]
                vc.nextResponder = sidebarController
            }
        }
    }
}
