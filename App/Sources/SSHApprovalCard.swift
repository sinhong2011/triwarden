import AppKit
import SwiftUI
import SSHAgent

/// The decision for one SSH signature, drawn as a card inside the menu bar panel.
struct SSHApprovalCard: View {
    var prompt: SSHPrompt
    var leadsWithUntilLock: Bool
    var choose: (SSHChoice) -> Void
    @State private var grant: SSHGrant

    init(prompt: SSHPrompt, leadsWithUntilLock: Bool, choose: @escaping (SSHChoice) -> Void) {
        self.prompt = prompt
        self.leadsWithUntilLock = leadsWithUntilLock
        self.choose = choose
        _grant = State(initialValue: leadsWithUntilLock ? .untilLock : .once)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(prompt.displayName) wants to sign")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    Text("via \(prompt.via) · \(prompt.keyName)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if prompt.appPath == nil, let path = prompt.path {
                Text(verbatim: path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if prompt.waitingCount > 1 {
                Text("^[\(prompt.waitingCount) signatures in this request](inflect: true)")
                    .font(.system(size: 12, weight: .medium))
            }
            if leadsWithUntilLock {
                Text("This app has asked to sign before.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Text("macOS will ask for Touch ID or your Mac login password. That password stays with macOS.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.menuCard, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.menuEdge))
    }

    private var icon: some View {
        Group {
            if let path = prompt.appPath {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
            } else {
                Image(systemName: "terminal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
    }

    @ViewBuilder private var actions: some View {
        VStack(spacing: 8) {
            Menu {
                Picker("How long", selection: $grant) {
                    Text("Allow Once").tag(SSHGrant.once)
                    Text("Allow for 10 Minutes").tag(SSHGrant.tenMinutes)
                    Text("Trust Until Lock").tag(SSHGrant.untilLock)
                    Text("Always Allow").tag(SSHGrant.always)
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 8) {
                    Text(grantTitle)
                        .font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 10, style: .continuous))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel(Text("How long to allow"))
            HStack(spacing: 8) {
                Button("Allow") { choose(.allow(grant)) }
                    .buttonStyle(.appPrimarySmall)
                    .keyboardShortcut(.defaultAction)
                Button("Deny") { choose(.deny) }
                    .buttonStyle(.appSecondarySmall)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: prompt.id) { _, _ in
            grant = leadsWithUntilLock ? .untilLock : .once
        }
    }

    private var grantTitle: LocalizedStringKey {
        switch grant {
        case .once: "Allow Once"
        case .tenMinutes: "Allow for 10 Minutes"
        case .untilLock: "Trust Until Lock"
        case .always: "Always Allow"
        }
    }
}

/// How long ago an SSH request was, in the largest unit only. Seconds are never shown.
enum SSHAccessClock {
    static func label(since date: Date, now: Date = .now) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date) / 60))
        if minutes < 1 { return String(localized: "Just now") }
        if minutes < 60 { return String(localized: "\(minutes) min") }
        let hours = minutes / 60
        if hours < 24 { return String(localized: "\(hours) hr") }
        return String(localized: "\(hours / 24) d")
    }
}

/// Shows the menu bar panel the same way a click on the icon does. Ordering the stored window
/// forward skips AppKit's status-item session: the generator stretches, and a click outside
/// never closes it. On macOS 27 that session is `_beginExpandedInterfaceSession:`; earlier
/// releases still use the button's click.
@MainActor
enum MenuBarOpener {
    static weak var panel: NSWindow?

    static var isOpen: Bool {
        if let item = statusItem(), isPresented(item) { return true }
        return panel.map { $0.isVisible && !$0.isMiniaturized } ?? false
    }

    @discardableResult
    static func open() -> Bool {
        guard let item = statusItem() else { return false }
        // A `.window` MenuBarExtra stays mounted, so `expandedInterfaceSession` can look
        // presented while the panel is hidden. Always begin a session unless the panel is
        // actually on screen.
        if let panel, panel.isVisible, isPresented(item) { return true }
        if let panel, panel.isVisible { panel.orderOut(nil) }
        present(item)
        return true
    }

    private static func present(_ item: NSStatusItem) {
        let begin = NSSelectorFromString("_beginExpandedInterfaceSession:")
        if item.responds(to: begin), let imp = item.method(for: begin) {
            // Must be later than the last session end. `.greatestFiniteMagnitude` only
            // works once: the next begin can never post-date it, so AppKit drops it.
            typealias Begin = @convention(c) (AnyObject, Selector, TimeInterval) -> Void
            unsafeBitCast(imp, to: Begin.self)(item, begin, ProcessInfo.processInfo.systemUptime)
            if panel?.isVisible == true { return }
        }
        item.button?.performClick(nil)
    }

    private static func isPresented(_ item: NSStatusItem) -> Bool {
        let session = NSSelectorFromString("expandedInterfaceSession")
        if item.responds(to: session),
           let value = item.perform(session)?.takeUnretainedValue(), !(value is NSNull) {
            return true
        }
        return item.button?.isHighlighted == true
    }

    private static func statusItem() -> NSStatusItem? {
        if let panel, let item = item(from: panel), isUsable(item) { return item }
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let item = item(from: window), isUsable(item) { return item }
        }
        let listed = listedItems()
        return listed.first(where: isOurs) ?? listed.first(where: isUsable)
    }

    private static func item(from window: NSWindow) -> NSStatusItem? {
        let sel = NSSelectorFromString("statusItem")
        if window.responds(to: sel) {
            return window.perform(sel)?.takeUnretainedValue() as? NSStatusItem
        }
        return Mirror(reflecting: window).descendant("statusItem") as? NSStatusItem
    }

    /// Other displays get an `NSStatusItemReplicant`; only the real item presents the panel.
    private static func isUsable(_ item: NSStatusItem) -> Bool {
        !item.className.contains("Replicant")
    }

    private static func isOurs(_ item: NSStatusItem) -> Bool {
        guard isUsable(item) else { return false }
        let button = item.button
        let desc = button?.image?.accessibilityDescription ?? ""
        let tip = button?.toolTip ?? ""
        let title = button?.title ?? ""
        return desc.localizedCaseInsensitiveContains("Triwarden")
            || tip.localizedCaseInsensitiveContains("Triwarden")
            || title.localizedCaseInsensitiveContains("Triwarden")
    }

    private static func listedItems() -> [NSStatusItem] {
        let bar = NSStatusBar.system
        let sel = NSSelectorFromString("_statusItems")
        guard bar.responds(to: sel), let value = bar.perform(sel)?.takeUnretainedValue() else { return [] }
        return (value as? [NSStatusItem]) ?? (value as? NSArray)?.compactMap { $0 as? NSStatusItem } ?? []
    }
}

/// Remembers the MenuBarExtra window so a leftover orderFront can be ordered out before a real open.
struct MenuBarPanelProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> Probe { Probe() }
    func updateNSView(_ view: Probe, context: Context) { view.register() }

    final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            register()
        }
        func register() {
            if let window { MenuBarOpener.panel = window }
        }
    }
}
