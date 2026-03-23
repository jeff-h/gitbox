import Cocoa

/// View-based replacement for the legacy cell-based GBSidebarCell.
/// Hosts an icon, title, badge, spinner, and optional action button as real subviews.
@objc(GBSidebarCellView)
class GBSidebarCellView: NSTableCellView, NSTextFieldDelegate {

    @objc static let cellIdentifier = NSUserInterfaceItemIdentifier("GBSidebarCellView")
    @objc static let rowHeight: CGFloat = 20

    private let iconImageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    let badgeView = GBBadgeView()
    private let spinnerView = NSProgressIndicator()
    private let actionButton = NSButton()

    /// The sidebar item this cell is displaying. Weak to avoid retain cycles.
    @objc weak var sidebarItem: GBSidebarItem?

    /// Set by the controller when the outline view is preparing a drag image.
    @objc var isDragging: Bool = false

    // Layout constants matching the original GBSidebarCell pixel values
    private static let iconSize: CGFloat = 16
    private static let iconLeftPadding: CGFloat = 3
    private static let iconRightPadding: CGFloat = 2
    private static let iconLeadingSpace: CGFloat = 6 // NSDivideRect leading slice
    private static let textYOffset: CGFloat = 3
    private static let spinnerSize: CGFloat = 16
    private static let extraRightPadding: CGFloat = 2
    private static let extraLeftPadding: CGFloat = 2

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
        // Icon
        iconImageView.imageScaling = .scaleProportionallyDown
        iconImageView.setContentHuggingPriority(.required, for: .horizontal)
        addSubview(iconImageView)

        // Title
        titleLabel.font = NSFont.systemFont(ofSize: 11)
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

        // Icon
        let image = item.image
        image?.size = NSSize(width: Self.iconSize, height: Self.iconSize)
        iconImageView.image = image

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

        needsLayout = true
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
        let iconX = Self.iconLeftPadding
        let iconY = round((bounds.height - Self.iconSize) / 2)
        iconImageView.frame = NSRect(x: iconX, y: iconY, width: Self.iconSize, height: Self.iconSize)

        // Right-side elements: action button > spinner > badge (first visible wins)
        var rightEdge = bounds.maxX - Self.extraRightPadding

        if !actionButton.isHidden {
            let buttonSize = actionButton.frame.size
            let buttonX = rightEdge - buttonSize.width
            let buttonY = round((bounds.height - buttonSize.height) / 2)
            actionButton.frame = NSRect(x: buttonX, y: buttonY, width: buttonSize.width, height: buttonSize.height)
            rightEdge = buttonX - Self.extraLeftPadding
        }

        if !spinnerView.isHidden {
            let spinnerX = rightEdge - Self.spinnerSize
            let spinnerY = round((bounds.height - Self.spinnerSize) / 2)
            spinnerView.frame = NSRect(x: spinnerX, y: spinnerY, width: Self.spinnerSize, height: Self.spinnerSize)
            rightEdge = spinnerX - Self.extraLeftPadding
        }

        if !badgeView.isHidden {
            let badgeSize = badgeView.intrinsicContentSize
            let badgeWidth = badgeSize.width
            let badgeX = rightEdge - badgeWidth
            badgeView.frame = NSRect(x: badgeX, y: 0, width: badgeWidth, height: bounds.height)
            rightEdge = badgeX - Self.extraLeftPadding
        }

        // Title: fills remaining space
        let textX = Self.iconLeadingSpace + Self.iconSize + Self.iconRightPadding
        let textWidth = max(rightEdge - textX, 0)
        titleLabel.frame = NSRect(x: textX, y: 0, width: textWidth, height: bounds.height)
    }

    // MARK: - Selection styling

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let isEmphasised = (backgroundStyle == .emphasized)

            // Title
            if isEmphasised {
                titleLabel.textColor = .alternateSelectedControlTextColor
                titleLabel.font = NSFont.boldSystemFont(ofSize: 11)
            } else {
                titleLabel.textColor = .controlTextColor
                titleLabel.font = NSFont.systemFont(ofSize: 11)
            }

            // Badge
            let isForeground = window?.isMainWindow ?? false
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
