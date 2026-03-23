import Cocoa

/// View-based replacement for the legacy cell-based GBSidebarCell.
/// Hosts an icon, title, badge, spinner, and optional action button as real subviews.
@objc(GBSidebarCellView)
class GBSidebarCellView: NSTableCellView, NSTextFieldDelegate {

    @objc static let cellIdentifier = NSUserInterfaceItemIdentifier("GBSidebarCellView")
    @objc static let rowHeight: CGFloat = 32

    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    let badgeView = GBBadgeView()
    private let spinnerView = NSProgressIndicator()
    private let actionButton = NSButton()

    /// The sidebar item this cell is displaying. Weak to avoid retain cycles.
    @objc weak var sidebarItem: GBSidebarItem?

    /// Set by the controller when the outline view is preparing a drag image.
    @objc var isDragging: Bool = false

    /// Whether the current icon is an SF Symbol (for tinting behaviour).
    private var iconIsSFSymbol: Bool = false

    // Layout constants — matching NNW's medium row style
    private static let iconSymbolSize: CGFloat = 18
    private static let iconFrameSize: CGFloat = 22
    private static let iconMarginLeft: CGFloat = 2
    private static let iconMarginRight: CGFloat = 5
    private static let fontSize: CGFloat = 13
    private static let spinnerSize: CGFloat = 16
    private static let rightPadding: CGFloat = 4
    private static let elementGap: CGFloat = 6

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupSubviews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupSubviews()
    }

    private func setupSubviews() {
        // Observe window main state for badge colouring
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowMainStateChanged),
            name: NSWindow.didBecomeMainNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowMainStateChanged),
            name: NSWindow.didResignMainNotification, object: nil)

        // Icon
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.contentTintColor = .secondaryLabelColor
        addSubview(iconImageView)

        // Title
        titleLabel.font = NSFont.systemFont(ofSize: Self.fontSize)
        titleLabel.textColor = .controlTextColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.isEditable = false
        titleLabel.isBordered = false
        titleLabel.drawsBackground = false
        addSubview(titleLabel)

        // Badge
        badgeView.isHidden = true
        addSubview(badgeView)

        // Spinner
        spinnerView.style = .spinning
        spinnerView.controlSize = .small
        spinnerView.isDisplayedWhenStopped = false
        spinnerView.isHidden = true
        addSubview(spinnerView)

        // Action button (e.g. "Download" / "Reset" for submodules)
        actionButton.bezelStyle = .roundRect
        actionButton.controlSize = .mini
        actionButton.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .mini))
        actionButton.isHidden = true
        addSubview(actionButton)

        // Expose standard NSTableCellView outlets
        textField = titleLabel
        imageView = iconImageView
    }

    // MARK: - Configuration

    @objc func configure(with item: GBSidebarItem) {
        sidebarItem = item

        // Editing — only if item opts in
        titleLabel.isEditable = item.isEditable
        titleLabel.delegate = item.isEditable ? self : nil

        // Icon — use the item's image, with SF Symbol fallbacks
        configureIcon(for: item)

        // Title
        titleLabel.stringValue = item.title ?? ""

        // Tooltip
        toolTip = item.tooltip

        // Context menu
        menu = item.menu

        // Action button (from GBSidebarItemObject protocol)
        configureActionButton(for: item)

        // Spinner vs badge (spinner takes priority, action button takes priority over both)
        let showSpinner = !item.isStopped() && item.visibleSpinning()
        configureSpinner(visible: showSpinner && actionButton.isHidden, progress: item.visibleProgress())

        if !showSpinner && actionButton.isHidden {
            let badge = Int(item.visibleBadgeInteger())
            badgeView.count = isDragging ? 0 : badge
        } else {
            badgeView.count = 0
        }

        // Keep badge colour in sync with window state on every refresh
        badgeView.isWindowForeground = window?.isMainWindow ?? true

        needsLayout = true
    }

    private func configureIcon(for item: GBSidebarItem) {
        iconIsSFSymbol = false

        // Section headers (REPOSITORIES) — no icon
        if item.isSection {
            iconImageView.image = nil
            iconImageView.isHidden = true
            iconImageView.contentTintColor = nil
            return
        }

        iconImageView.isHidden = false
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: Self.iconSymbolSize, weight: .regular)
        var symbolName: String
        var accessibilityDesc: String

        // Check if this is an uncloned submodule
        if let obj = item.object,
           obj.responds(to: #selector(GBSidebarItemObject.sidebarItemActionButtonTitle)),
           let title = obj.sidebarItemActionButtonTitle?(),
           title == NSLocalizedString("Download", comment: "") {
            symbolName = "folder.fill.badge.questionmark"
            accessibilityDesc = "Not downloaded"
        } else if item.object is GBRepositoriesGroup {
            symbolName = "folder"
            accessibilityDesc = "Group"
        } else {
            symbolName = "folder.fill"
            accessibilityDesc = "Repository"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDesc)?
            .withSymbolConfiguration(symbolConfig)
        iconIsSFSymbol = true
        iconImageView.image = image
        iconImageView.contentTintColor = .controlAccentColor
    }

    private func configureActionButton(for item: GBSidebarItem) {
        guard let obj = item.object,
              obj.responds(to: #selector(GBSidebarItemObject.sidebarItemActionButtonTitle)),
              let title = obj.sidebarItemActionButtonTitle?(),
              !title.isEmpty,
              obj.responds(to: #selector(GBSidebarItemObject.sidebarItemActionButtonAction)),
              let action = obj.sidebarItemActionButtonAction?()
        else {
            actionButton.isHidden = true
            return
        }

        actionButton.title = title
        actionButton.action = action
        actionButton.target = obj
        actionButton.sizeToFit()
        actionButton.isHidden = false
    }

    private func configureSpinner(visible: Bool, progress: Double) {
        if visible {
            spinnerView.isHidden = false
            let isIndeterminate = progress <= 1.0 || progress >= 99.9
            spinnerView.isIndeterminate = isIndeterminate
            if !isIndeterminate {
                spinnerView.doubleValue = max(min(progress, 100.0), 6.0)
            }
            spinnerView.startAnimation(nil)
        } else {
            spinnerView.stopAnimation(nil)
            spinnerView.isHidden = true
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        let bounds = self.bounds

        // Icon: left-aligned, vertically centred
        let iconX = Self.iconMarginLeft
        let iconY = round((bounds.height - Self.iconFrameSize) / 2)
        iconImageView.frame = NSRect(x: iconX, y: iconY, width: Self.iconFrameSize, height: Self.iconFrameSize)

        // Right-side elements: action button > spinner > badge (first visible wins)
        var rightEdge = bounds.maxX - Self.rightPadding

        if !actionButton.isHidden {
            let buttonSize = actionButton.frame.size
            let buttonX = rightEdge - buttonSize.width
            let buttonY = round((bounds.height - buttonSize.height) / 2)
            actionButton.frame = NSRect(x: buttonX, y: buttonY, width: buttonSize.width, height: buttonSize.height)
            rightEdge = buttonX - Self.elementGap
        }

        if !spinnerView.isHidden {
            let spinnerX = rightEdge - Self.spinnerSize
            let spinnerY = round((bounds.height - Self.spinnerSize) / 2)
            spinnerView.frame = NSRect(x: spinnerX, y: spinnerY, width: Self.spinnerSize, height: Self.spinnerSize)
            rightEdge = spinnerX - Self.elementGap
        }

        if !badgeView.isHidden {
            let badgeSize = badgeView.intrinsicContentSize
            let badgeWidth = badgeSize.width
            let badgeX = rightEdge - badgeWidth
            badgeView.frame = NSRect(x: badgeX, y: 0, width: badgeWidth, height: bounds.height)
            rightEdge = badgeX - Self.elementGap
        }

        // Title: fills remaining space between icon and right-side elements
        let textX: CGFloat
        if iconImageView.isHidden {
            textX = Self.iconMarginLeft
        } else {
            textX = Self.iconMarginLeft + Self.iconFrameSize + Self.iconMarginRight
        }
        let textWidth = max(rightEdge - textX, 0)
        let textHeight = titleLabel.intrinsicContentSize.height
        let textY = round((bounds.height - textHeight) / 2)
        titleLabel.frame = NSRect(x: textX, y: textY, width: textWidth, height: textHeight)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Selection styling

    @objc private func windowMainStateChanged(_ notification: Notification) {
        guard let notifWindow = notification.object as? NSWindow,
              notifWindow == window else { return }
        let isForeground = notifWindow.isMainWindow
        badgeView.isWindowForeground = isForeground
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let isEmphasised = (backgroundStyle == .emphasized)

            // Title
            titleLabel.textColor = isEmphasised ? .alternateSelectedControlTextColor : .controlTextColor

            // Icon tint — white when selected for SF Symbols
            if iconIsSFSymbol {
                iconImageView.contentTintColor = isEmphasised ? .alternateSelectedControlTextColor : .controlAccentColor
            }

            // Badge — default to true when window is nil (cell not yet in hierarchy)
            let isForeground = window?.isMainWindow ?? true
            badgeView.isEmphasised = isEmphasised
            badgeView.isWindowForeground = isForeground

            needsLayout = true
        }
    }

    // MARK: - NSTextFieldDelegate (editing)

    func control(_ control: NSControl, textShouldEndEditing fieldEditor: NSText) -> Bool {
        let text = fieldEditor.string.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        sidebarItem?.setStringValue(textField.stringValue)
    }
}
