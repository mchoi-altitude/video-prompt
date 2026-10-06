import AppKit
import VPApp

/// The menu-bar icon and its menu, rebuilt from `menuItems(...)` each time it opens.
@MainActor
final class StatusItem: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let items: () -> [MenuItemModel]
    private let onAction: (MenuAction) -> Void

    init(items: @escaping () -> [MenuItemModel], onAction: @escaping (MenuAction) -> Void) {
        self.items = items
        self.onAction = onAction
        super.init()
        menu.delegate = self
        item.menu = menu
        setBadge(.none)
    }

    func setBadge(_ badge: MenuBadge) {
        guard let symbol = NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Video Prompt") else { return }
        let size = NSSize(width: 18, height: 18)
        let tint: NSColor? = switch badge {
        case .none: nil
        case .waiting: NSColor(srgbRed: 0xF0 / 255, green: 0xA0 / 255, blue: 0x20 / 255, alpha: 1)
        case .recording: NSColor(srgbRed: 0xD0 / 255, green: 0x31 / 255, blue: 0x3A / 255, alpha: 1)
        }
        guard let tint else { symbol.isTemplate = true; item.button?.image = symbol; return }
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect.insetBy(dx: 1, dy: 1))
            if badge == .recording {
                tint.setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: 6, dy: 6)).fill()
            } else {
                tint.setFill(); NSBezierPath(ovalIn: NSRect(x: rect.maxX - 7, y: rect.maxY - 7, width: 7, height: 7)).fill()
            }
            return true
        }
        image.isTemplate = false
        item.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for (i, m) in items().enumerated() {
            if m.action == .recordings || (m.action == .recordChrome && i > 0) || (m.action == .header && i > 0) { menu.addItem(.separator()) }
            let mi = NSMenuItem(title: m.title, action: m.enabled ? #selector(pick(_:)) : nil, keyEquivalent: "")
            mi.target = self
            mi.representedObject = m.action
            mi.state = m.checked ? .on : .off
            mi.isEnabled = m.enabled
            if let sub = m.subtitle {
                if #available(macOS 14.4, *) { mi.subtitle = sub } else { mi.toolTip = sub }
            }
            if let s = m.shortcut {
                let t = NSMutableAttributedString(string: m.title)
                t.append(NSAttributedString(string: "\t\(s)", attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
                let ps = NSMutableParagraphStyle()
                ps.tabStops = [NSTextTab(textAlignment: .right, location: 260)]
                t.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: t.length))
                mi.attributedTitle = t
            }
            if m.action == .header {
                mi.attributedTitle = NSAttributedString(string: "● " + m.title, attributes: [
                    .foregroundColor: NSColor(srgbRed: 0x9A / 255, green: 0x5A / 255, blue: 0x06 / 255, alpha: 1),
                    .font: NSFont.menuFont(ofSize: 0).withWeight(.medium)])
            }
            menu.addItem(mi)
        }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        if let a = sender.representedObject as? MenuAction { onAction(a) }
    }
}

private extension NSFont {
    func withWeight(_ w: NSFont.Weight) -> NSFont { NSFont.systemFont(ofSize: pointSize, weight: w) }
}
