import Cocoa

@objc(GBBadgeView)
class GBBadgeView: NSView {

    @objc var count: Int = 0 {
        didSet {
            isHidden = count <= 0
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// Whether the parent row is emphasised (selected in a key/main window).
    @objc var isEmphasised: Bool = false {
        didSet { needsDisplay = true }
    }

    /// Whether the containing window is the main window.
    @objc var isWindowForeground: Bool = true {
        didSet { needsDisplay = true }
    }

    private static let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
    private static let minWidth: CGFloat = 20
    private static let horizontalPadding: CGFloat = 7
    private static let badgeHeight: CGFloat = 18

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        guard count > 0 else { return .zero }
        let textWidth = badgeString.size(withAttributes: textAttributes).width
        let width = max(ceil(textWidth) + Self.horizontalPadding * 2, Self.minWidth)
        return NSSize(width: width, height: bounds.height)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard count > 0 else { return }

        // Centre the pill vertically within bounds
        let pillRect = NSRect(
            x: 0,
            y: round((bounds.height - Self.badgeHeight) / 2),
            width: bounds.width,
            height: Self.badgeHeight
        )
        let cornerRadius = Self.badgeHeight / 2

        // Background pill — fully rounded capsule
        let path = NSBezierPath(roundedRect: pillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        path.fill()

        // Centred text within the pill
        let attrs = textAttributes
        let textSize = badgeString.size(withAttributes: attrs)
        let textRect = NSRect(
            x: round((pillRect.width - textSize.width) / 2),
            y: pillRect.origin.y + round((pillRect.height - textSize.height) / 2),
            width: textSize.width,
            height: textSize.height
        )
        badgeString.draw(in: textRect, withAttributes: attrs)
    }

    // MARK: - Colours

    /// Uses system colours so badges look correct across light/dark mode
    /// and adapt properly when selected.
    private var fillColor: NSColor {
        if isEmphasised {
            return .white
        }
        if isWindowForeground {
            return .controlAccentColor
        }
        return .tertiaryLabelColor
    }

    private var textColor: NSColor {
        if isEmphasised {
            return .controlAccentColor
        }
        return .white
    }

    private var textAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byTruncatingTail
        return [
            .font: Self.font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private var badgeString: String {
        "\(count)"
    }
}
