import AppKit
import VPApp

/// The menu-bar icon and its menu, rebuilt from `menuItems(...)` each time it opens.
@MainActor
final class StatusItem: NSObject, NSMenuDelegate {
    private let item: NSStatusItem = {
        // New icons go to the left end of the right side of the menu bar; on a full menu bar
        // that's under the camera notch. Ask for the far right (next to Control Center)
        // unless the user has dragged it somewhere themselves.
        let key = "NSStatusItem Preferred Position VideoPrompt"
        if UserDefaults.standard.object(forKey: key) == nil { UserDefaults.standard.set(0.0, forKey: key) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "VideoPrompt"
        return item
    }()
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [item] in
            let f = item.button?.window?.frame ?? .zero
            log.notice("status item visible=\(item.isVisible, privacy: .public) frame=\(NSStringFromRect(f), privacy: .public)")
        }
    }

    func setBadge(_ badge: MenuBadge) {
        item.button?.image = switch badge {
        case .none: MenuIcon.idle()
        case .waiting: MenuIcon.waiting()
        case .recording: MenuIcon.recording()
        }
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
