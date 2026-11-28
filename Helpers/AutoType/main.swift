// Triwarden Auto-Type: types a login into another app for Triwarden. It lives inside Triwarden.app
// (Contents/Library/Helpers) and is the only part that needs Accessibility, so the app itself stays sandboxed.
// It listens on a short Unix socket (path published in the App Group) and answers only Triwarden: the binary of the app bundle
// it sits in, signed by the same team. It keeps nothing, and quits with Triwarden.
import AppKit
import ApplicationServices
import os

/// Diagnostics only (no secrets): who's in front when typing, and why a request failed.
let log = Logger(subsystem: "io.github.sinhong2011.triwarden", category: "autotype-helper")
import Security
import SSHAgent

let appGroup = "FX3VR69P5K.io.github.sinhong2011.triwarden"

/// …/Triwarden.app, four levels up from …/Contents/Library/Helpers/Triwarden Auto-Type.app.
let hostApp = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let hostExecutable = Bundle(url: hostApp)?.executableURL?.resolvingSymlinksInPath().path

// MARK: Who may ask

/// Our own signing team, if we're signed (development builds may not be).
let ownTeam: String? = {
    var me: SecCode?
    var staticCode: SecStaticCode?
    var info: CFDictionary?
    guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
          SecCodeCopyStaticCode(me, [], &staticCode) == errSecSuccess, let staticCode,
          SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
    else { return nil }
    return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
}()

/// Triwarden itself: the executable of the bundle we're in, and (when we're signed) signed by our team.
func isHost(_ peer: FramedSocketServer.Peer) -> Bool {
    guard let path = peer.path, let hostExecutable,
          URL(fileURLWithPath: path).resolvingSymlinksInPath().path == hostExecutable else { return false }
    guard let team = ownTeam else { return true }
    var code: SecCode?
    var requirement: SecRequirement?
    let attributes = [kSecGuestAttributePid: peer.pid] as CFDictionary
    guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess, let code,
          SecRequirementCreateWithString("anchor apple generic and certificate leaf[subject.OU] = \"\(team)\"" as CFString,
                                         [], &requirement) == errSecSuccess
    else { return false }
    return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
}

// MARK: Typing

/// Events from a private source, so keys the user still holds (⌃ from ⌃↵) don't leak into the text.
nonisolated(unsafe) let source = CGEventSource(stateID: .privateState)

/// Where typed keys go: the system's keyboard focus (nil), or straight to one app's process when the focus is stuck
/// elsewhere (a closed panel of Triwarden's can keep it, though the app itself is in front).
func post(_ key: CGKeyCode, text: [UniChar] = [], to pid: pid_t? = nil) {
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
        event.flags = []
        if !text.isEmpty { event.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text) }
        if let pid { event.postToPid(pid) } else { event.post(tap: .cghidEventTap) }
    }
    usleep(7_000)
}

/// The app that has the keyboard right now, system-wide, and the role of its focused element (diagnostics).
func keyboardFocus() -> (pid: pid_t?, role: String) {
    let system = AXUIElementCreateSystemWide()
    var app: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &app) == .success, let app,
          CFGetTypeID(app) == AXUIElementGetTypeID() else { return (nil, "?") }
    let appElement = app as! AXUIElement
    var pid: pid_t = 0
    AXUIElementGetPid(appElement, &pid)
    var element: CFTypeRef?
    var role: CFTypeRef?
    if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &element) == .success,
       let element, CFGetTypeID(element) == AXUIElementGetTypeID() {
        AXUIElementCopyAttributeValue(element as! AXUIElement, kAXRoleAttribute as CFString, &role)
    }
    return (pid, (role as? String) ?? "none")
}

/// Waits (briefly) for the user to let go of ⌘ ⌥ ⌃ ⇧ from the shortcut that asked for typing.
func waitForModifiers() {
    let held: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    for _ in 0..<75 where !CGEventSource.flagsState(.combinedSessionState).intersection(held).isEmpty { usleep(20_000) }
}

/// Brings `pid` forward and waits until it is the front app.
func bringForward(_ pid: pid_t) async -> Bool {
    await MainActor.run {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != pid { app.activate() }
        return true
    } ? await waitUntilFront(pid) : false
}

func waitUntilFront(_ pid: pid_t) async -> Bool {
    for _ in 0..<50 {
        if await MainActor.run(body: { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }) {
            refocus(pid)
            try? await Task.sleep(for: .milliseconds(120)) // let its window take focus
            return true
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return false
}

/// Gives the app's window the keyboard again. A panel of ours (the menu bar's) can take it from the front app
/// without that app ever losing the front; when the panel goes, nothing hands it back, and typing then lands in a
/// window that isn't listening (a beep). Through Accessibility: the app frontmost, its window main and raised.
func refocus(_ pid: pid_t) {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    var value: CFTypeRef?
    let focused = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success && value != nil
    if !focused { AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value) }
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
        log.error("refocus: \(pid) has no window to focus")
        return
    }
    let window = value as! AXUIElement
    AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    log.debug("refocus: \(pid) window \(focused ? "was focused" : "had lost focus", privacy: .public)")
}

func type(_ steps: [AutoTypeProtocol.Request.Step], into pid: pid_t) {
    waitForModifiers()
    let focus = keyboardFocus()
    // The keyboard is with someone else (Triwarden's closed panel): deliver to the app itself.
    let direct: pid_t? = focus.pid == pid ? nil : pid
    log.debug("type: keyboard with \(focus.pid ?? -1) (role \(focus.role, privacy: .public)), target \(pid), \(direct == nil ? "system-wide" : "direct to app", privacy: .public)")
    for step in steps {
        switch step {
        case .text(let text): for character in text { post(0, text: Array(String(character).utf16), to: direct) }
        case .tab: post(0x30, to: direct)
        case .enter: post(0x24, to: direct)
        }
    }
}

// MARK: Serving

var lastRequest = Date()

func handle(_ data: Data, _ peer: FramedSocketServer.Peer) async -> Data {
    let encoder = JSONEncoder()
    func reply(_ failure: AutoTypeProtocol.Response.Failure? = nil, trusted: Bool = AXIsProcessTrusted()) -> Data {
        (try? encoder.encode(AutoTypeProtocol.Response(trusted: trusted, failure: failure))) ?? Data()
    }
    // Anyone else learns nothing, not even whether typing is allowed.
    guard isHost(peer), let request = try? JSONDecoder().decode(AutoTypeProtocol.Request.self, from: data) else {
        return reply(.badRequest, trusted: false)
    }
    await MainActor.run { lastRequest = Date() }
    switch request.action {
    case .status:
        return reply()
    case .askPermission:
        // The system prompt, which offers to open Privacy & Security › Accessibility.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) // kAXTrustedCheckOptionPrompt
        return reply()
    case .type:
        guard AXIsProcessTrusted() else { log.error("type: no Accessibility permission"); return reply(.permission) }
        guard await bringForward(request.pid) else {
            let front = await MainActor.run { NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?" }
            log.error("type: target \(request.pid) never came to the front (front: \(front, privacy: .public))")
            return reply(.target)
        }
        type(request.steps, into: request.pid)
        return reply()
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Triwarden Auto-Type: \(message)\n".utf8))
    exit(1)
}

let socketPath: String
do {
    socketPath = try UnixSocketLocation.prepareBindPath(kind: .autotype)
} catch {
    fail("couldn't prepare socket: \(error.localizedDescription)")
}
let server = FramedSocketServer(socketURL: URL(fileURLWithPath: socketPath)) { data, peer in
    await handle(data, peer)
}
do {
    try server.start()
    try UnixSocketLocation.publish(kind: .autotype, socketPath: socketPath)
} catch {
    fail("couldn't listen: \(error.localizedDescription)")
}

// Quit with Triwarden (it passes its pid); started any other way, quit after ten idle minutes.
let arguments = CommandLine.arguments
var parentWatch: DispatchSourceProcess?
if let at = arguments.firstIndex(of: "--parent"), at + 1 < arguments.count, let parent = pid_t(arguments[at + 1]) {
    let watch = DispatchSource.makeProcessSource(identifier: parent, eventMask: .exit, queue: .main)
    watch.setEventHandler { server.stop(); UnixSocketLocation.unpublish(kind: .autotype); exit(0) }
    watch.resume()
    parentWatch = watch
    if kill(parent, 0) != 0 { server.stop(); UnixSocketLocation.unpublish(kind: .autotype); exit(0) }
} else {
    Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
        MainActor.assumeIsolated {
            if Date().timeIntervalSince(lastRequest) > 600 { server.stop(); UnixSocketLocation.unpublish(kind: .autotype); exit(0) }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.run()
