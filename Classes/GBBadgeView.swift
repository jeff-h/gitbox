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

    private static let font = NSFont.boldSystemFont(ofSize: 11)
    private static let minWidth: CGFloat = 20
    private static let cornerRadius: CGFloat = 8
    private static let horizontalPadding: CGFloat = 4

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

        let rect = bounds

        // Background pill
        let path = NSBezierPath(roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        fillColor.setFill()
        path.fill()

        // Centred text
        let attrs = textAttributes
        let textSize = badgeString.size(withAttributes: attrs)
        let textRect = NSRect(
            x: round((rect.width - textSize.width) / 2),
            y: round((rect.height - textSize.height) / 2),
            width: textSize.width,
            height: textSize.height
        )
        badgeString.draw(in: textRect, withAttributes: attrs)
    }

    // MARK: - Colours

    /// Matches the original GBSidebarCell colour scheme exactly.
    private var fillColor: NSColor {
        if isEmphasised {
            return .white
        }
        if isWindowForeground {
            return NSColor(calibratedHue: 217.0 / 360.0, saturation: 0.27, brightness: 0.79, alpha: 1.0)
        }
        return NSColor(calibratedHue: 0, saturation: 0, brightness: 0.67, alpha: 0.8)
    }

    private var textColor: NSColor {
        if isEmphasised {
            if isWindowForeground {
                return NSColor(calibratedHue: 217.0 / 360.0, saturation: 0.40, brightness: 0.70, alpha: 1.0)
            }
            return .gray
        }
        if isWindowForeground {
            return .white
        }
        return NSColor(calibratedHue: 0, saturation: 0, brightness: 0.50, alpha: 0.8)
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
