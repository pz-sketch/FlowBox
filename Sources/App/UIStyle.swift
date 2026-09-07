import AppKit

enum UIStyle {
    static let windowWidth: CGFloat = 680
    static let windowHeight: CGFloat = 580
    static let minimumWindowWidth: CGFloat = 520
    static let minimumWindowHeight: CGFloat = 420
    static let outerPadding: CGFloat = 24
    static let cardRadius: CGFloat = 12
    static let cardBorderAlpha: CGFloat = 0.08
    static let separatorAlpha: CGFloat = 0.08
    static let sectionSpacing: CGFloat = 18
    static let cardInnerMargin: CGFloat = 14
    static let headerIconSize: CGFloat = 28
    static let controlHeight: CGFloat = 26
    static let smallControlHeight: CGFloat = 24

    static var accent: NSColor { NSColor.controlAccentColor }
    static var windowBackground: NSColor { NSColor.windowBackgroundColor }
    static var controlBackground: NSColor { NSColor.controlBackgroundColor }
    static var label: NSColor { NSColor.labelColor }
    static var secondaryLabel: NSColor { NSColor.secondaryLabelColor }
    static var tertiaryLabel: NSColor { NSColor.tertiaryLabelColor }

    static func cardBoxStyle(_ box: NSBox) {
        box.boxType = .custom
        box.borderWidth = 1
        box.borderColor = NSColor.separatorColor.withAlphaComponent(cardBorderAlpha)
        box.cornerRadius = cardRadius
        box.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.68)
        box.titlePosition = .noTitle
        box.wantsLayer = true
        box.layer?.shadowColor = NSColor.black.cgColor
        box.layer?.shadowOpacity = 0.04
        box.layer?.shadowRadius = 14
        box.layer?.shadowOffset = NSSize(width: 0, height: 6)
        box.layer?.masksToBounds = false
    }

    static func softCard(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cardRadius
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(cardBorderAlpha).cgColor
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.68).cgColor
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowOpacity = 0.04
        view.layer?.shadowRadius = 14
        view.layer?.shadowOffset = NSSize(width: 0, height: 6)
    }

    static let subtitleColor = NSColor.secondaryLabelColor
    static let hintColor = NSColor.tertiaryLabelColor

    static func separatorColor() -> NSColor {
        NSColor.separatorColor.withAlphaComponent(separatorAlpha)
    }

    static func titleFont(size: CGFloat = 13, weight: NSFont.Weight = .semibold) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func subtitleFont() -> NSFont {
        .systemFont(ofSize: 11, weight: .regular)
    }

    static func pillButton(_ button: NSButton, filled: Bool = false) {
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.masksToBounds = true
        if filled {
            button.bezelStyle = .inline
            button.isBordered = false
            button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            button.contentTintColor = .white
        } else {
            button.bezelStyle = .rounded
            button.layer?.borderWidth = 1
            button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.14).cgColor
            button.layer?.backgroundColor = controlBackground.withAlphaComponent(0.9).cgColor
        }
    }

    static func smallIconButton(_ button: NSButton) {
        button.bezelStyle = .inline
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9).cgColor
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.10).cgColor
        button.contentTintColor = secondaryLabel
    }

    static func badgeLabel(_ label: NSTextField) {
        label.wantsLayer = true
        label.layer?.cornerRadius = 6
        label.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        label.textColor = NSColor.controlAccentColor
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.alignment = .center
    }
}
