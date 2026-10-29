import AppKit
import SecretsAgent
import SSHAgent
import SwiftUI

/// One temporary approval shown at the top of the screen. Names and references only, never a key value.
struct NotchAccessItem: Identifiable, Equatable {
    enum Source: Equatable { case tool(UUID), ssh(String) }
    let source: Source
    let symbol: String
    let title: String
    let detail: String
    /// Nil lasts until the vault locks.
    let expires: Date?
    /// The vault account the keys come from, when more than one is signed in (an email, or "2 accounts").
    var account: String? = nil
    var id: String {
        switch source {
        case .tool(let id): "tool-" + id.uuidString
        case .ssh(let id): "ssh-" + id
        }
    }
}

/// Where the user wants the status. The notch falls back to a centred capsule on screens without one.
enum NotchPosition: String, CaseIterable {
    case notch, topLeft, topRight, custom

    var title: String {
        switch self {
        case .notch: String(localized: "At the notch")
        case .topLeft: String(localized: "Top left")
        case .topRight: String(localized: "Top right")
        case .custom: String(localized: "Where I drag it")
        }
    }

    /// The top centre the user dragged the status to, if any.
    static var savedOrigin: CGPoint? {
        get {
            let parts = (UserDefaults.standard.string(forKey: Pref.accessStatusOrigin) ?? "").split(separator: ",").compactMap { Double($0) }
            return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
        }
        set {
            UserDefaults.standard.set(newValue.map { "\(Int($0.x)),\(Int($0.y))" }, forKey: Pref.accessStatusOrigin)
        }
    }

    static var current: NotchPosition {
        UserDefaults.standard.string(forKey: Pref.accessStatusPosition).flatMap(Self.init) ?? .notch
    }
}

/// Where the status sits: around the camera housing, or as a floating capsule on screens without one.
struct NotchGeometry: Equatable {
    var notchWidth: CGFloat
    var height: CGFloat
    var hasNotch: Bool

    static let wing: CGFloat = 64
    static let expandedWidth: CGFloat = 440
    static let rowHeight: CGFloat = 48
    static let heroHeight: CGFloat = 104
    static let footerHeight: CGFloat = 52
    static let maxRows = 4
    /// The concave flare where the shape meets the screen's top edge.
    static let shoulder: CGFloat = 8

    static func of(_ screen: NSScreen) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return .init(notchWidth: screen.frame.width - left.width - right.width, height: top, hasNotch: true)
        }
        return .init(notchWidth: 0, height: 32, hasNotch: false)
    }

    var collapsed: CGSize {
        hasNotch ? CGSize(width: notchWidth + Self.wing * 2 + Self.shoulder * 2, height: height)
                 : CGSize(width: 212, height: height)
    }

    var request: CGSize { CGSize(width: max(collapsed.width, Self.expandedWidth), height: height + 132) }

    func expanded(rows: Int) -> CGSize {
        // The soonest approval is the hero; the rest sit in a list under it.
        let others = max(0, rows - 1)
        let listed = min(others, Self.maxRows - 1) + (others > Self.maxRows - 1 ? 1 : 0)
        return CGSize(width: max(collapsed.width, Self.expandedWidth),
                      height: height + Self.heroHeight + CGFloat(listed) * Self.rowHeight + (listed > 0 ? 10 : 0) + Self.footerHeight)
    }
}

/// Another app that keeps its own window over the notch (NotchNook, Boring Notch and the like). Settings reads it
/// to explain why the status moved.
@MainActor @Observable
final class NotchOccupancy {
    static let shared = NotchOccupancy()
    private(set) var owner: String?

    /// Window owners that are part of macOS itself, never a notch app.
    private static let system: Set<String> = ["Window Server", "Dock", "SystemUIServer", "Control Center", "ControlCenter",
                                              "WindowManager", "Notification Center", "NotificationCenter", "Spotlight", "loginwindow"]

    /// Looks for another app's window covering the camera housing. Reads only window owners and frames, which needs
    /// no permission. The full-width menu bar and ordinary app windows don't count.
    func check(_ screen: NSScreen) {
        owner = Self.occupant(on: screen)
    }

    static func occupant(on screen: NSScreen) -> String? {
        guard screen.safeAreaInsets.top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        // Window bounds are measured from the top-left of the primary screen.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let notch = CGRect(x: screen.frame.minX + left.width, y: primaryHeight - screen.frame.maxY,
                           width: screen.frame.width - left.width - right.width, height: screen.safeAreaInsets.top)
        let me = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in windows {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) != me,
                  let name = info[kCGWindowOwnerName as String] as? String, !system.contains(name),
                  (info[kCGWindowLayer as String] as? Int ?? 0) > 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let b = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"] else { continue }
            let frame = CGRect(x: x, y: y, width: w, height: h)
            // Wider than most of the screen is a bar, not a notch app.
            guard w < screen.frame.width * 0.8, frame.intersection(notch).width >= notch.width * 0.5 else { continue }
            return name
        }
        return nil
    }
}

/// An approval waiting for an answer, shown in the notch instead of a window. References and names only.
struct NotchRequest: Identifiable {
    enum Kind { case ssh, tool }
    enum Choice { case deny, once, tenMinutes, untilLock, review }
    let id: UUID
    let kind: Kind
    let symbol: String
    let title: String
    let subtitle: String
    let detail: String
    let deadline: Date
    var waiting = 1
    var leadsWithUntilLock = false
    var busy = false
    let choose: (Choice) -> Void
}

@MainActor @Observable
final class NotchStatusState {
    var items: [NotchAccessItem] = []
    var expanded = false
    var geometry = NotchGeometry(notchWidth: 200, height: 32, hasNotch: true)
    /// Which edge the capsule grows from, so a corner placement opens away from the screen edge.
    var alignment: HorizontalAlignment = .center
    /// False while growing out of the notch and while shrinking back into it.
    var present = false
    /// Shown in place of the list until answered.
    var request: NotchRequest?
}

/// Shows active temporary access at the notch while there is any. Hovering opens the list, where each approval
/// can be ended. The panel never activates the app or takes focus, and it holds no key values.
@MainActor
final class NotchStatusController {
    private weak var model: AppModel?
    private let state = NotchStatusState()
    private var panel: NSPanel?
    private var screen: NSScreen?
    private var position = NotchPosition.notch
    private var known: Set<String> = []
    private var started = false
    private var hovering = false
    private var ticker: Task<Void, Never>?
    private var pendingCollapse: Task<Void, Never>?
    private var pendingExpand: Task<Void, Never>?
    private var pendingHide: Task<Void, Never>?
    /// The front app fills the notch's screen (a video, a slideshow), so the status steps aside.
    private var fullScreen = false
    private var observers: [Any] = []
    #if DEBUG
    /// Sample rows for trying the motion. Display only: nothing is granted, and End just drops the row.
    private var demo: [NotchAccessItem] = []
    private var demoEnd: Task<Void, Never>?

    func showDemo() {
        demo = [
            .init(source: .tool(UUID()), symbol: "sparkles", title: "Claude Code", detail: "zsh (PID 4120) · 1 key", expires: .now.addingTimeInterval(90)),
            .init(source: .ssh("demo-github"), symbol: "key.fill", title: "Terminal", detail: "GitHub development", expires: .now.addingTimeInterval(45)),
            .init(source: .tool(UUID()), symbol: "shippingbox", title: "Storefront dev server", detail: "zsh (PID 3311) · 3 keys", expires: nil)
        ]
        refresh()
        demoEnd?.cancel()
        demoEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(90))
            guard !Task.isCancelled else { return }
            self?.demo = []; self?.refresh()
        }
    }

    /// A sample SSH request; any answer just clears it.
    func showRequestDemo() {
        present(NotchRequest(id: UUID(), kind: .ssh, symbol: "key.fill", title: "Terminal", subtitle: "wants to sign with GitHub development",
                             detail: "git", deadline: .now.addingTimeInterval(60), waiting: 2) { [weak self] _ in self?.clearRequest(.ssh) })
    }
    #endif

    /// A built-in display with a camera housing: the notch features start on there, and off on other Macs,
    /// until the user chooses in Settings.
    /// Read once screens are known and refreshed when they change, never from inside a defaults notification:
    /// AppKit's first `NSScreen.screens` registers defaults inside a dispatch_once, and reading screens again from
    /// the change it posts locks that once recursively (a launch-time crash, seen in CI's demo launch).
    static private(set) var macHasNotch = false
    private static func readScreens() { macHasNotch = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 } }

    static var enabled: Bool { UserDefaults.standard.object(forKey: Pref.accessStatus) as? Bool ?? macHasNotch }

    init(model: AppModel) {
        self.model = model
        Self.readScreens()
        observe()
        let center = NotificationCenter.default
        // Settings changes arrive here too. Hop to the next turn so nothing runs inside the poster's own work
        // (see `macHasNotch`).
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { Self.readScreens(); self?.place() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkFullScreen() }
            })
        }
        // A notch app starting or quitting changes who owns the notch.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Give a launching app a moment to put its window up.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.placeIfShown() }
                }
            })
        }
        refresh()
        started = true
        #if DEBUG
        if CommandLine.arguments.contains("--notch-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showDemo() }
            // Remote checks without pointer access: `notifyutil -p io.github.sinhong2011.triwarden.notch.expand`.
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: .init("io.github.sinhong2011.triwarden.notch.request"), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.showRequestDemo() }
            })
            for (name, open) in [("expand", true), ("collapse", false)] {
                observers.append(DistributedNotificationCenter.default().addObserver(
                    forName: .init("io.github.sinhong2011.triwarden.notch." + name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if open { self?.expand() } else { self?.hovering = false; self?.collapse(after: .zero) } }
                })
            }
        }
        #endif
    }

    /// Re-reads the approvals whenever either store changes. Expiry is time-based, so the ticker covers that.
    private func observe() {
        withObservationTracking { [weak self] in
            guard let self, let model else { return }
            _ = model.secrets.activeGrants
            _ = model.secrets.profiles
            _ = model.sshAgent.activeTrusts
        } onChange: { [weak self] in
            Task { @MainActor in self?.refresh(); self?.observe() }
        }
    }

    private func refresh() {
        guard let model else { return }
        var items = Self.enabled ? Self.items(model) : []
        #if DEBUG
        demo.removeAll { $0.expires.map { $0 <= .now } ?? false }
        items += demo
        #endif
        let fresh = items.filter { !known.contains($0.id) }
        known = Set(items.map(\.id))
        state.items = items
        if let request = state.request, fullScreen || !Self.hostsApprovals {
            // Somewhere the notch can't be seen: answer in a window instead.
            state.request = nil
            request.choose(.review)
        }
        guard !items.isEmpty || state.request != nil, !fullScreen else { hide(); return }
        if panel != nil, position != NotchPosition.current { place() }
        show()
        if started, !fresh.isEmpty { announce() }
        if state.expanded { resize(animated: false) }
    }

    static func items(_ model: AppModel) -> [NotchAccessItem] {
        let profiles = Dictionary(model.secrets.profiles.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        // Name the account only when there is more than one to tell apart.
        let several = model.sessions.count > 1
        func account(_ ids: [String]) -> String? {
            guard several else { return nil }
            let unique = Array(Set(ids))
            if unique.count > 1 { return String(localized: "\(unique.count) accounts") }
            return unique.first.flatMap { id in model.accounts.first { $0.id == id }?.email }
        }
        let tools = model.secrets.activeGrants.map { grant in
            let profile = profiles[grant.tool]
            let count = profile?.bindings.count ?? 0
            let keys = count == 1 ? String(localized: "1 key") : count > 1 ? String(localized: "\(count) keys") : nil
            return NotchAccessItem(source: .tool(grant.id), symbol: profile.map(ToolGlyph.symbol) ?? "terminal",
                                   title: profile?.title ?? String(localized: "Unavailable tool"),
                                   detail: [grant.caller.label, keys].compactMap { $0 }.joined(separator: " · "),
                                   expires: grant.deadline.map { Date.now.addingTimeInterval(Self.seconds(ContinuousClock.now.duration(to: $0))) },
                                   account: account(profile?.bindings.map(\.accountID) ?? []))
        }
        let ssh = model.sshAgent.activeTrusts.map { trust in
            NotchAccessItem(source: .ssh(trust.id), symbol: "key.fill", title: trust.displayName, detail: trust.keyName, expires: trust.until,
                            account: account(model.items.filter { $0.id == trust.keyID }.map(\.accountId)))
        }
        // Soonest to end first; until-lock approvals after the timed ones.
        return (tools + ssh).sorted { ($0.expires ?? .distantFuture) < ($1.expires ?? .distantFuture) }
    }

    static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }

    // MARK: Panel

    private func show() {
        if panel == nil {
            let panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.title = String(localized: "Active access")
            let view = NotchStatusView(state: state, hover: { [weak self] in self?.hover($0) }, toggle: { [weak self] in self?.toggle() },
                                       drag: { [weak self] in self?.drag($0) },
                                       end: { [weak self] in self?.end($0) }, openAccess: { [weak self] in self?.openAccess() })
                .modifier(ReducedMotionPolicy())
            let host = NotchHostingView(rootView: AnyView(view))
            host.shape = { [weak self] in self?.hitRect() ?? .zero }
            // The controller sizes the panel; SwiftUI must not resize it to the content's ideal size.
            host.sizingOptions = []
            panel.contentView = host
            self.panel = panel
            CaptureShield.apply(panel)
        }
        pendingHide?.cancel(); pendingHide = nil
        place()
        if panel?.isVisible == false {
            state.present = false
            panel?.orderFrontRegardless()
            // One frame at notch size, then grow out of it.
            Task { @MainActor [weak self] in self?.state.present = true }
        } else { state.present = true }
        startTicker()
    }

    /// Shrinks back into the notch, then leaves the screen.
    private func hide() {
        ticker?.cancel(); ticker = nil
        pendingCollapse?.cancel(); pendingExpand?.cancel()
        hovering = false
        guard let panel, panel.isVisible, pendingHide == nil else { return }
        state.expanded = false
        state.present = false
        pendingHide = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            guard let self, !Task.isCancelled else { return }
            panel.orderOut(nil)
            pendingHide = nil
            resize(animated: false)
        }
    }

    /// True when another app is full screen on the status's screen. A full-screen window covers the whole
    /// frame, menu bar included.
    func checkFullScreen() {
        guard let screen = screen ?? NSScreen.screens.first else { return }
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let covering = windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == front, front != ProcessInfo.processInfo.processIdentifier,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"] else { return false }
            // Window bounds are top-left based; flip into AppKit's bottom-left space.
            let frame = CGRect(x: x, y: mainHeight - y - h, width: w, height: h)
            return frame.insetBy(dx: -1, dy: -1).contains(screen.frame)
        }
        guard covering != fullScreen else { return }
        fullScreen = covering
        refresh()
    }

    /// The screen with a notch if there is one, else the main screen. Corners always use the capsule.
    private func placeIfShown() {
        if panel?.isVisible == true, !state.expanded { place() }
    }

    private func place() {
        position = NotchPosition.current
        if position == .custom, NotchPosition.savedOrigin == nil { position = .notch }
        if position == .notch, let notched = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            // Another app owns the notch: sharing it would stack two shapes and fight over hover, so step aside.
            NotchOccupancy.shared.check(notched)
            if NotchOccupancy.shared.owner != nil { position = .topRight }
        }
        let screen: NSScreen? = switch position {
        // Without a notch, the screen with the menu bar: the key window's screen moves with focus, and a status
        // on a side display goes unseen.
        case .notch: NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
        case .custom: NotchPosition.savedOrigin.flatMap { point in NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) } } ?? NSScreen.screens.first
        case .topLeft, .topRight: NSScreen.screens.first
        }
        guard let screen else { return }
        self.screen = screen
        var geometry = NotchGeometry.of(screen)
        if position != .notch { geometry = .init(notchWidth: 0, height: 32, hasNotch: false) }
        state.geometry = geometry
        state.alignment = position == .topLeft ? .leading : position == .topRight ? .trailing : .center
        resize(animated: false)
    }

    /// The panel is sized to the largest shape it may show, so SwiftUI can animate the outline freely inside it
    /// instead of the window jumping. Clicks outside the visible shape pass through to whatever is underneath.
    private var canvas: CGSize {
        let g = state.geometry
        let largest = [g.collapsed, g.expanded(rows: state.items.count), state.request != nil ? g.request : .zero]
        return CGSize(width: largest.map(\.width).max() ?? 0, height: (largest.map(\.height).max() ?? 0) + 30)
    }

    private func resize(animated: Bool) {
        guard let panel, let screen else { return }
        let size = canvas
        var top = state.geometry.hasNotch ? screen.frame.maxY : screen.visibleFrame.maxY - 6
        let margin: CGFloat = 10
        var x = switch position {
        case .notch: screen.frame.midX - size.width / 2
        case .topLeft: screen.visibleFrame.minX + margin
        case .topRight: screen.visibleFrame.maxX - margin - size.width
        case .custom: (NotchPosition.savedOrigin?.x ?? screen.frame.midX) - size.width / 2
        }
        if position == .custom, let origin = NotchPosition.savedOrigin {
            // Keep the whole panel, open or closed, on the screen.
            let visible = screen.visibleFrame
            top = min(max(origin.y, visible.minY + size.height), visible.maxY)
            x = min(max(x, visible.minX), visible.maxX - size.width)
        }
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true, animate: animated)
    }

    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    // MARK: Interaction

    // MARK: Dragging

    private var dragStart: (mouse: CGPoint, origin: CGPoint)?

    /// Moving the status anywhere switches to the dragged position and remembers it. Closed while moving, so the
    /// list doesn't sweep across the screen.
    private func drag(_ phase: NotchDragPhase) {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .changed:
            if dragStart == nil {
                pendingExpand?.cancel(); pendingCollapse?.cancel()
                if state.expanded { state.expanded = false; resize(animated: false) }
                state.geometry = .init(notchWidth: 0, height: 32, hasNotch: false)
                state.alignment = .center
                let size = state.geometry.collapsed
                panel.setFrame(NSRect(x: mouse.x - size.width / 2, y: panel.frame.maxY - size.height, width: size.width, height: size.height), display: true)
                dragStart = (mouse, CGPoint(x: panel.frame.midX, y: panel.frame.maxY))
            }
            guard let start = dragStart else { return }
            let center = CGPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y)
            panel.setFrameTopLeftPoint(CGPoint(x: center.x - panel.frame.width / 2, y: center.y))
        case .ended:
            guard dragStart != nil else { return }
            dragStart = nil
            NotchPosition.savedOrigin = CGPoint(x: panel.frame.midX, y: panel.frame.maxY)
            UserDefaults.standard.set(NotchPosition.custom.rawValue, forKey: Pref.accessStatusPosition)
            place()
        }
    }

    private func expand() {
        pendingCollapse?.cancel()
        guard !state.expanded else { return }
        state.expanded = true
        resize(animated: false)
    }

    private func collapse(after delay: Duration) {
        pendingCollapse?.cancel()
        pendingCollapse = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, !hovering, state.request == nil else { return }
            state.expanded = false
        }
    }

    /// A short pause before opening, so passing the pointer to the menu bar doesn't throw the list open.
    private func hover(_ inside: Bool) {
        hovering = inside
        pendingExpand?.cancel()
        if inside {
            pendingCollapse?.cancel()
            pendingExpand = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(160))
                guard let self, !Task.isCancelled, hovering else { return }
                expand()
            }
        } else { collapse(after: .milliseconds(300)) }
    }

    private func toggle() {
        pendingExpand?.cancel()
        if state.expanded { hovering = false; collapse(after: .zero) } else { expand() }
    }

    /// Opens the list from outside the panel (the menu bar menu), which can't be reached by pointer or keyboard.
    func reveal() {
        guard !state.items.isEmpty else { openAccess(); return }
        if fullScreen { openAccess(); return }
        expand()
        collapse(after: .seconds(6))
    }

    var hasItems: Bool { !state.items.isEmpty }

    // MARK: Requests

    static var hostsApprovals: Bool { (UserDefaults.standard.string(forKey: Pref.approvalStyle) ?? defaultApprovalStyle) == "notch" }
    static var defaultApprovalStyle: String { macHasNotch ? "notch" : "window" }

    /// The notch can take a request now: chosen in Settings, and not hidden behind a full-screen app.
    func canPresentRequest() -> Bool {
        checkFullScreen()
        return Self.hostsApprovals && !fullScreen && !NSScreen.screens.isEmpty
    }

    /// Shows or updates a waiting request. The same request refreshing (a new waiting count) keeps its state.
    func present(_ request: NotchRequest) {
        var request = request
        if let current = state.request, current.id == request.id { request.busy = current.busy }
        let fresh = state.request?.id != request.id
        state.request = request
        show()
        state.expanded = true
        resize(animated: false)
        if fresh {
            // The panel takes keys only while asking, so Return and Esc answer without clicking.
            (panel as? NotchPanel)?.acceptsKey = true
            panel?.makeKey()
        }
    }

    func markBusy(_ id: UUID) {
        if state.request?.id == id { state.request?.busy = true }
    }

    func clearRequest(_ kind: NotchRequest.Kind) {
        guard state.request?.kind == kind else { return }
        state.request = nil
        (panel as? NotchPanel)?.acceptsKey = false
        panel?.resignKey()
        state.expanded = false
        refresh()
        resize(animated: false)
    }

    /// A new approval opens the list briefly, so the user sees what just got access.
    private func announce() {
        expand()
        collapse(after: .seconds(3))
    }

    private func end(_ item: NotchAccessItem) {
        #if DEBUG
        if demo.contains(item) { demo.removeAll { $0 == item }; refresh(); return }
        #endif
        switch item.source {
        case .tool(let id): model?.secrets.revokeGrant(id)
        case .ssh(let id): model?.sshAgent.revokeTrust(id: id)
        }
        refresh()
    }

    private func openAccess() {
        model?.requestedSection = .access
        model?.bringToFront()
        hovering = false
        collapse(after: .zero)
    }

    /// The visible shape, in the hosting view's coordinates (origin bottom-left).
    private func hitRect() -> CGRect {
        let g = state.geometry
        let size = state.request != nil ? g.request : state.expanded ? g.expanded(rows: state.items.count) : g.collapsed
        let canvas = canvas
        let x: CGFloat = switch state.alignment {
        case .leading: 0
        case .trailing: canvas.width - size.width
        default: (canvas.width - size.width) / 2
        }
        return CGRect(x: x, y: canvas.height - size.height, width: size.width, height: size.height)
    }
}

/// Passes clicks and hover outside the drawn shape through, so the transparent part of the panel never blocks
/// the menu bar or windows below.
private final class NotchHostingView: NSHostingView<AnyView> {
    var shape: () -> CGRect = { .zero }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return shape().contains(local) ? super.hitTest(point) : nil
    }
}

private final class NotchPanel: NSPanel {
    var acceptsKey = false
    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }
}

// MARK: View

/// The hardware notch's outline: flat top flush with the screen edge, concave shoulders flaring into the bezel,
/// then rounded bottom corners. Both radii animate, so the bar can grow into a panel and back.
struct NotchOutline: Shape {
    var shoulder: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(shoulder, bottom) }
        set { shoulder = newValue.first; bottom = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let s = min(shoulder, rect.width / 4), b = min(bottom, (rect.width - s * 2) / 2, rect.height - s)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s, y: rect.minY + s), control: CGPoint(x: rect.minX + s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - b))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s + b, y: rect.maxY), control: CGPoint(x: rect.minX + s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s - b, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - s, y: rect.maxY - b), control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - s, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

enum NotchDragPhase { case changed, ended }

/// Black like the camera housing it grows out of, in light and dark mode alike.
struct NotchStatusView: View {
    let state: NotchStatusState
    var hover: (Bool) -> Void = { _ in }
    var toggle: () -> Void = {}
    var drag: (NotchDragPhase) -> Void = { _ in }
    var end: (NotchAccessItem) -> Void = { _ in }
    var openAccess: () -> Void = {}

    private var geometry: NotchGeometry { state.geometry }
    private var size: CGSize {
        if !state.present {
            return geometry.hasNotch ? CGSize(width: geometry.notchWidth + NotchGeometry.shoulder * 2, height: geometry.height)
                                     : CGSize(width: 44, height: 10)
        }
        if state.request != nil { return geometry.request }
        return state.expanded ? geometry.expanded(rows: state.items.count) : geometry.collapsed
    }
    private var bottomRadius: CGFloat { state.expanded ? 36 : geometry.hasNotch ? 10 : geometry.height / 2 }
    private var shoulder: CGFloat { state.expanded ? 14 : NotchGeometry.shoulder }
    /// One spring for size, corners and content, so they move as one. Interruptible: reversing mid-way carries
    /// the current velocity instead of restarting.
    private var spring: Animation { .interpolatingSpring(mass: 1, stiffness: 260, damping: 26) }
    private var contentIn: AnyTransition {
        .modifier(active: NotchContentReveal(progress: 0), identity: NotchContentReveal(progress: 1))
    }
    private var inset: CGFloat { geometry.hasNotch ? shoulder : 0 }

    var body: some View {
        ZStack(alignment: .top) {
            outline.fill(.black)
            VStack(spacing: 0) {
                // Open, the hero says the same thing larger, so the strip steps back to leave the camera clear.
                band.frame(height: geometry.height).opacity(state.present && !state.expanded ? 1 : 0)
                    .contentShape(.rect).onTapGesture(perform: toggle)
                    .gesture(DragGesture(minimumDistance: 12, coordinateSpace: .global)
                        .onChanged { _ in drag(.changed) }.onEnded { _ in drag(.ended) })
                if let request = state.request {
                    NotchRequestCard(request: request)
                        .transition(.asymmetric(insertion: contentIn.animation(spring.delay(0.05)),
                                                removal: contentIn.animation(.easeIn(duration: 0.1))))
                } else if state.expanded {
                    list.transition(.asymmetric(insertion: contentIn.animation(spring.delay(0.05)),
                                                removal: contentIn.animation(.easeIn(duration: 0.1))))
                }
            }.padding(.horizontal, inset)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(outline)
        .compositingGroup()
        .shadow(color: .black.opacity(state.expanded || state.request != nil ? 0.35 : 0), radius: 18, y: 8)
        .contentShape(outline)
        .onHover(perform: hover)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: state.alignment, vertical: .top))
        .environment(\.colorScheme, .dark)
        .opacity(state.present || geometry.hasNotch ? 1 : 0)
        .animation(spring, value: state.expanded)
        .animation(spring, value: state.present)
        .animation(spring, value: state.items.map(\.id))
        .animation(spring, value: state.request?.id)
        .animation(spring, value: state.request?.busy)
    }

    private var outline: AnyShape {
        geometry.hasNotch ? AnyShape(NotchOutline(shoulder: shoulder, bottom: bottomRadius))
                          : AnyShape(RoundedRectangle(cornerRadius: state.expanded ? 36 : geometry.height / 2, style: .continuous))
    }

    // MARK: Collapsed

    /// What has access on the left, how long on the right, the camera in between.
    private var band: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                glyph(state.items.first, size: 20)
                if state.items.count > 1 {
                    Text(verbatim: "+\(state.items.count - 1)").font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6)).monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            if geometry.hasNotch { Spacer(minLength: geometry.notchWidth) } else {
                Text(verbatim: state.items.first?.title ?? "").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 4)
            }
            countdown(state.items.first, ring: 18)
        }
        .padding(.leading, geometry.hasNotch ? 14 : 8).padding(.trailing, geometry.hasNotch ? 12 : 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(state.items.count == 1 ? "1 app or tool has temporary access" : "\(state.items.count) apps or tools have temporary access"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { toggle() }
    }

    // MARK: Expanded

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let first = state.items.first { hero(first) }
            let rest = Array(state.items.dropFirst())
            if !rest.isEmpty {
                VStack(spacing: 0) {
                    ForEach(rest.prefix(NotchGeometry.maxRows - 1)) { item in row(item) }
                    if rest.count > NotchGeometry.maxRows - 1 {
                        Button(action: openAccess) {
                            Text("\(rest.count - (NotchGeometry.maxRows - 1)) more in Access").font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5)).frame(maxWidth: .infinity).frame(height: NotchGeometry.rowHeight)
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 5)
                .background(.white.opacity(0.06), in: .rect(cornerRadius: 20, style: .continuous))
                .padding(.horizontal, 14)
            }
            footer
        }
    }

    /// The approval that ends first, at a size you can read from across the desk.
    private func hero(_ item: NotchAccessItem) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(tint(item)).frame(width: 6, height: 6)
                    Text(verbatim: item.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint(item)).lineLimit(1)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let expires = item.expires {
                        let left = max(0, Int(expires.timeIntervalSince(context.date)))
                        Text(verbatim: String(format: "%02d:%02d", left / 60, left % 60))
                            .font(.system(size: 38, weight: .bold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(left <= 60 ? Color.orange : .white)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: left)
                    } else {
                        Text("Until lock").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                }
                Text(verbatim: [item.detail, item.account].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            VStack(spacing: 8) {
                ZStack {
                    progressRing(item, diameter: 52, line: 4)
                    glyph(item, size: 30)
                }
                endButton(item, prominent: true)
            }
        }
        .padding(.horizontal, 24).frame(height: NotchGeometry.heroHeight)
    }

    private var footer: some View {
        HStack {
            Text("Temporary access").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.4))
            Spacer()
            Button(action: openAccess) {
                HStack(spacing: 4) {
                    Text("Open Access")
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
                }
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(.white.opacity(0.22)))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 24).frame(height: NotchGeometry.footerHeight)
    }

    private func row(_ item: NotchAccessItem) -> some View {
        NotchRow(item: item, glyph: glyph(item, size: 30), countdown: countdown(item, ring: 26), end: endButton(item, prominent: false))
    }

    // MARK: Pieces

    /// Tools get a soft colour so they read apart at a glance; SSH keys and plain programs stay neutral.
    private func tint(_ item: NotchAccessItem?) -> Color {
        switch item?.symbol {
        case "sparkles": .orange
        case "shippingbox": .green
        case "chevron.left.forwardslash.chevron.right": .yellow
        default: .white
        }
    }

    /// Time left out of ten minutes; until-lock approvals show a full, quiet ring.
    private func progressRing(_ item: NotchAccessItem, diameter: CGFloat, line: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = item.expires.map { max(0, $0.timeIntervalSince(context.date)) }
            let color: Color = left.map { $0 <= 60 ? .orange : tint(item) == .white ? .green : tint(item) } ?? .white.opacity(0.3)
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: line)
                Circle().trim(from: 0, to: left.map { min(1, $0 / 600) } ?? 1)
                    .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left.map(Int.init))
            }.frame(width: diameter, height: diameter)
        }.accessibilityHidden(true)
    }

    private func endButton(_ item: NotchAccessItem, prominent: Bool) -> some View {
        NotchEndButton(prominent: prominent) { end(item) }
            .accessibilityLabel(Text("End access for \(item.title)"))
    }

    private func glyph(_ item: NotchAccessItem?, size: CGFloat) -> some View {
        let tint = tint(item)
        return Image(systemName: item?.symbol ?? "key.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint == .white ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(tint))
            .frame(width: size, height: size)
            .background(tint.opacity(tint == .white ? 0.12 : 0.2), in: .rect(cornerRadius: size * 0.3, style: .continuous))
    }

    /// A ring that empties as the approval runs out, with the time beside it. Until-lock shows a lock instead.
    @ViewBuilder private func countdown(_ item: NotchAccessItem?, ring: CGFloat) -> some View {
        if let item {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let expires = item.expires {
                    let left = max(0, expires.timeIntervalSince(context.date))
                    let urgent = left <= 60
                    let tint: Color = urgent ? .orange : .green
                    HStack(spacing: 6) {
                        Text(verbatim: String(format: "%d:%02d", Int(left) / 60, Int(left) % 60))
                            .font(.system(size: ring > 20 ? 12 : 11, weight: .semibold, design: .rounded)).monospacedDigit()
                            .foregroundStyle(urgent ? Color.orange : .white.opacity(0.85))
                            .contentTransition(.numericText(countsDown: true))
                        ZStack {
                            Circle().stroke(.white.opacity(0.14), lineWidth: 2.5)
                            Circle().trim(from: 0, to: min(1, left / 600))
                                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        }.frame(width: ring * 0.62, height: ring * 0.62)
                    }
                    .animation(.linear(duration: 1), value: Int(left))
                    .accessibilityLabel(Text(verbatim: String(format: "%d:%02d", Int(left) / 60, Int(left) % 60)))
                } else {
                    Image(systemName: "lock.open.fill").font(.system(size: ring > 20 ? 11 : 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: ring * 0.62, height: ring * 0.62)
                        .help(Text("Until the vault locks"))
                        .accessibilityLabel(Text("Until the vault locks"))
                }
            }
        }
    }
}

/// One approval in the list: glyph, name and detail, the time left, and End. Highlights under the pointer.
private struct NotchRow<Glyph: View, Countdown: View, End: View>: View {
    let item: NotchAccessItem
    let glyph: Glyph
    let countdown: Countdown
    let end: End
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 12) {
            glyph
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: item.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(verbatim: [item.detail, item.account].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            countdown
            end
        }
        .padding(.horizontal, 10).frame(height: NotchGeometry.rowHeight)
        .background(.white.opacity(hovered ? 0.06 : 0), in: .rect(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 5)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// End, as a capsule: filled for the hero, quiet in the list. Red only under the pointer, where it means it.
private struct NotchEndButton: View {
    let prominent: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("End").font(.system(size: prominent ? 12 : 11, weight: .semibold))
                .foregroundStyle(hovered ? Color.red : .white.opacity(0.9))
                .padding(.horizontal, prominent ? 16 : 11).padding(.vertical, prominent ? 6 : 5)
                .background(hovered ? AnyShapeStyle(Color.red.opacity(0.18)) : AnyShapeStyle(.white.opacity(prominent ? 0.16 : 0.1)), in: Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}

/// An approval answered in the notch: who asks for what, the time left, and the choices. Return allows (once, or
/// until lock when that leads), Esc denies, and Details opens the full card. macOS authentication still follows.
private struct NotchRequestCard: View {
    let request: NotchRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: request.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                    .frame(width: 38, height: 38).background(.white.opacity(0.12), in: .rect(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: request.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(verbatim: request.subtitle).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 8)
                countdown
            }
            HStack(spacing: 6) {
                Text(verbatim: request.detail).lineLimit(1).truncationMode(.middle)
                if request.waiting > 1 {
                    Text(verbatim: "·")
                    Text("\(request.waiting - 1) more waiting")
                }
            }.font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            if request.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Confirm with Touch ID or your password…").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                }.frame(height: 30)
            } else {
                HStack(spacing: 6) {
                    pill("Deny", style: .quiet) { request.choose(.deny) }.keyboardShortcut(.cancelAction)
                    pill("Details…", style: .text) { request.choose(.review) }
                    Spacer(minLength: 4)
                    pill("10 min", style: .quiet) { request.choose(.tenMinutes) }
                    if request.leadsWithUntilLock {
                        pill("Once", style: .quiet) { request.choose(.once) }
                        pill("Until Lock", style: .primary) { request.choose(.untilLock) }.keyboardShortcut(.defaultAction)
                    } else {
                        pill("Until Lock", style: .quiet) { request.choose(.untilLock) }
                        pill("Allow Once", style: .primary) { request.choose(.once) }.keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(.horizontal, 22).padding(.bottom, 18).padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: request.title + ", " + request.subtitle))
    }

    private var countdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, Int(request.deadline.timeIntervalSince(context.date).rounded(.up)))
            HStack(spacing: 6) {
                Text(verbatim: "\(left)s").font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(left <= 10 ? Color.orange : .white.opacity(0.7))
                    .contentTransition(.numericText(countsDown: true))
                ZStack {
                    Circle().stroke(.white.opacity(0.12), lineWidth: 2.5)
                    Circle().trim(from: 0, to: min(1, Double(left) / 60))
                        .stroke(left <= 10 ? Color.orange : .white.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }.frame(width: 16, height: 16)
            }.animation(.linear(duration: 1), value: left)
        }
    }

    private enum PillStyle { case primary, quiet, text }

    private func pill(_ title: LocalizedStringKey, style: PillStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style == .primary ? Color.black : .white.opacity(style == .text ? 0.55 : 0.9))
                .padding(.horizontal, style == .text ? 4 : 12).padding(.vertical, 7)
                .background(style == .primary ? AnyShapeStyle(Color.white) : AnyShapeStyle(.white.opacity(style == .text ? 0 : 0.12)), in: Capsule())
                .fixedSize()
        }.buttonStyle(.plain)
    }
}

/// Content arriving in the notch: fades in, rises from slightly smaller and loses a little blur, the way the
/// shape around it settles.
private struct NotchContentReveal: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.94 + 0.06 * progress, anchor: .top)
            .blur(radius: (1 - progress) * 6)
    }
}

