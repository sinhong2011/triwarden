import AppKit
import SecretsAgent
import SwiftUI

/// Installing tw needs an administrator, which a sandboxed app can't be: Triwarden copies the command and opens
/// Terminal, then watches for the link so the user never has to come back and check.
struct TerminalHelperSetup: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var installation: TerminalHelperInstallation?
    @State private var waiting = false
    @State private var showsCommand = false
    #if DEBUG
    var previewInstallation: TerminalHelperInstallation?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormHeader(symbol: "terminal", title: "Terminal Helper",
                       subtitle: "Start saved tools from any terminal with tw.").padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let installation {
                        if installation.state == .installed { installed } else { install(installation) }
                        details(installation)
                    } else {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 24)
            }.thinScroller()
            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(installation?.state == .installed ? .appPrimary : .appSecondary)
                    .keyboardShortcut(.cancelAction)
            }.padding(20)
        }
        .frame(width: 560, height: 640).background { WindowBackdrop() }
        .task { await inspect() }
        // After Terminal is opened, look for the new link until it appears or the sheet closes.
        .task(id: waiting) {
            guard waiting else { return }
            while !Task.isCancelled, installation?.state != .installed {
                try? await Task.sleep(for: .seconds(1.5))
                await inspect()
            }
            waiting = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await inspect() }
        }
    }

    private var installed: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("tw is installed").font(.system(size: 15, weight: .semibold))
                    Text("It uses the helper inside this copy of Triwarden.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Try it in a new terminal window").font(.system(size: 12, weight: .semibold))
                CommandWell(command: "tw tools list", copyLabel: "Copy") { model.copyPlain("tw tools list") }
                Text("It lists your saved tools and the command that starts each one. It shows no keys.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))
    }

    @ViewBuilder private func install(_ installation: TerminalHelperInstallation) -> some View {
        if let command = installation.installCommand {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(installation.state == .wrongLink ? "Point tw at this app" : "Install tw")
                        .font(.system(size: 15, weight: .semibold))
                    Text("macOS needs your password to add tw to /usr/local/bin, so the last step happens in Terminal.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    step(1, "Copy the command and open Terminal")
                    step(2, "Paste with ⌘V and press Return")
                    step(3, "Enter your Mac password")
                }
                HStack(spacing: 12) {
                    Button { copyAndOpenTerminal(command) } label: {
                        Label("Copy & Open Terminal", systemImage: "terminal")
                    }.buttonStyle(.appPrimary).keyboardShortcut(.defaultAction).accessibilityIdentifier("installHelper")
                    if waiting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Waiting for tw…").font(.system(size: 12)).foregroundStyle(.secondary)
                        }.transition(.opacity)
                    }
                }
                DisclosureGroup("Show command", isExpanded: $showsCommand) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: command).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.primary.opacity(0.045), in: .rect(cornerRadius: 10, style: .continuous))
                        Text("It links /usr/local/bin/tw to the helper in this app. It replaces only an existing link, never a file.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 8)
                }.font(.system(size: 12))
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))
            .animation(.snappy(duration: 0.2), value: waiting)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 16)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 6) {
                    Text("tw can't be installed yet").font(.system(size: 14, weight: .semibold))
                    Text(verbatim: installation.instruction).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))
        }
    }

    private func details(_ installation: TerminalHelperInstallation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !Self.isPermanentLocation(installation.source) {
                Label("This copy of Triwarden isn't in Applications. Move it there first, or tw stops working when this copy moves.",
                      systemImage: "exclamationmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                row("Installs to", installation.destination.path)
                Divider().opacity(0.4).padding(.leading, 14)
                row("Links to", installation.source.path)
            }
            .background(Color.panel, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.panelEdge))
            Text("Triwarden never edits .zshrc or other shell files. If another tw runs instead, check with command -v tw.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: String(number)).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .frame(width: 20, height: 20).overlay(Circle().strokeBorder(.primary.opacity(0.2)))
                .accessibilityHidden(true)
            Text(text).font(.system(size: 13))
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 76, alignment: .leading)
            Text(verbatim: value).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                .lineLimit(2).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func copyAndOpenTerminal(_ command: String) {
        model.copyPlain(command)
        if let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminal, configuration: .init())
        }
        model.flash(String(localized: "Command copied. Paste it in Terminal with ⌘V."))
        waiting = true
    }

    private func inspect() async {
        #if DEBUG
        if let previewInstallation { installation = previewInstallation; return }
        #endif
        let app = Bundle.main.bundleURL
        installation = await Task.detached(priority: .utility) { TerminalHelperInstallation.inspect(appURL: app) }.value
    }

    private static func isPermanentLocation(_ helper: URL) -> Bool {
        let path = helper.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/Applications/")
    }
}
