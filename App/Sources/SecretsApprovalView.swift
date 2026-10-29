import SwiftUI
import SecretsAgent

/// Reference-only presentation shared by the live panel and synthetic visual previews.
struct SecretsApprovalView: View {
    let prompt: SecretsController.Prompt
    var authenticating = false
    var deny: () -> Void
    var allow: (SecretsGrantDuration) -> Void
    @State private var helperExpanded = false
    @State private var duration: SecretsGrantDuration = .once

    init(prompt: SecretsController.Prompt, authenticating: Bool = false, deny: @escaping () -> Void,
         allow: @escaping (SecretsGrantDuration) -> Void, initialDuration: SecretsGrantDuration = .once) {
        self.prompt = prompt; self.authenticating = authenticating; self.deny = deny; self.allow = allow
        _duration = State(initialValue: initialDuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    keysGroup
                    commandGroup
                    caveats
                }
                .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 20)
            }
            .thinScroller()
            footer
        }
        .frame(minWidth: 540, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity)
        .background { WindowBackdrop() }
    }

    /// Who is asking, for which tool: the question the user answers.
    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ToolGlyph(profile: prompt.request.profile, size: 46)
            VStack(alignment: .leading, spacing: 5) {
                Text("Start \(Text(verbatim: prompt.request.profile.title)) with your keys?")
                    .font(.system(size: 17, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 6) {
                    if let caller = prompt.caller {
                        Label { Text(verbatim: caller.label) } icon: { Image(systemName: "terminal") }
                    } else {
                        Label("Launcher not verified", systemImage: "questionmark.circle").foregroundStyle(.orange)
                    }
                    Text(verbatim: "·").foregroundStyle(.tertiary)
                    Text(verbatim: ToolLaunchesPane.abbreviated(prompt.request.launch.directory))
                        .lineLimit(1).truncationMode(.middle)
                }.font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    /// Keys from one account name it once, under the group; mixed accounts name it on each row.
    private var sharedAccount: String? {
        let accounts = Set(requestedKeys.map(\.account))
        return accounts.count == 1 ? accounts.first : nil
    }

    private var keysGroup: some View {
        group(requestedKeys.count == 1 ? "1 key" : "\(requestedKeys.count) keys", note: sharedAccount.map { String(localized: "From \($0)") }) {
            ForEach(requestedKeys) { credential in
                HStack(spacing: 12) {
                    Image(systemName: "key.fill").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: credential.name).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                        if sharedAccount == nil {
                            Text(verbatim: credential.account).font(.system(size: 11)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: credential.variable)
                        .font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.primary.opacity(0.05), in: .rect(cornerRadius: 6, style: .continuous))
                        .lineLimit(1).fixedSize()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .accessibilityElement(children: .combine)
                if credential.id != requestedKeys.last?.id { Divider().opacity(0.4).padding(.leading, 52) }
            }
        }
    }

    private var commandGroup: some View {
        group("Runs") {
            row("Program", prompt.request.launch.executable.path)
            ForEach(Array(prompt.request.profile.arguments.enumerated()), id: \.offset) { index, argument in
                Divider().opacity(0.4).padding(.leading, 14)
                row("Argument \(index + 1)", argument.isEmpty ? String(localized: "(empty argument)") : argument)
            }
            Divider().opacity(0.4).padding(.leading, 14)
            row("In folder", prompt.request.launch.directory)
            Divider().opacity(0.4).padding(.leading, 14)
            DisclosureGroup(isExpanded: $helperExpanded) {
                Text(verbatim: prompt.helper)
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            } label: {
                Text("Requested by").font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.horizontal, 14).padding(.vertical, 9)
        }
    }

    private var caveats: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("A terminal or an AI agent may have asked for this launch. Allow it only if you just started it.", systemImage: "info.circle")
            Text("The tool and anything it starts can read and keep these keys. Locking Triwarden can't take them back, and approving doesn't check the project's code.")
                .padding(.leading, 20)
        }
        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if prompt.caller != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        Text("Allow for").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        AppSegmented(options: [(.once, "Once"), (.tenMinutes, "10 minutes"), (.untilLock, "Until lock")],
                                     selection: $duration, compact: true)
                            .frame(maxWidth: 260)
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("How long to allow")
                            .accessibilityIdentifier("secretsApprovalDuration")
                            .disabled(authenticating)
                    }
                    Text(durationDescription).font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Only this launch can be allowed, because the terminal or launcher that asked could not be verified.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                DeadlineCountdown(deadline: prompt.deadline, duration: SecretsController.approvalTimeout)
                // Drops out rather than wrapping when the card is narrow; the button's help keeps it.
                ViewThatFits(in: .horizontal) {
                    Label(authenticationMessage, systemImage: "touchid")
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
                Spacer(minLength: 8)
                Button("Deny", action: deny).buttonStyle(.appSecondary).keyboardShortcut(.cancelAction)
                Button { allow(prompt.caller == nil ? .once : duration) } label: {
                    HStack(spacing: 6) {
                        if authenticating { ProgressView().controlSize(.small).tint(.white) }
                        Text(allowTitle)
                    }
                }.buttonStyle(.appPrimary).disabled(authenticating).help(Text(authenticationMessage))
            }
        }
        .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 16)
        .background(alignment: .top) { Divider().opacity(0.5) }
    }

    private func group<Content: View>(_ title: LocalizedStringKey, note: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    .textCase(.uppercase).tracking(0.4)
                if let note {
                    Text(verbatim: note).font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }.padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content() }
                .background(Color.panelStrong, in: .rect(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.panelEdge))
        }
    }

    private var requestedKeys: [SecretsController.Prompt.Credential] {
        if !prompt.credentials.isEmpty { return prompt.credentials }
        return [.init(name: prompt.credential, account: prompt.account, field: prompt.request.profile.field.label,
                      variable: prompt.request.profile.variable)]
    }

    private var authenticationMessage: LocalizedStringKey {
        authenticating ? "Waiting for macOS…" : "Touch ID or your Mac password"
    }

    private var allowTitle: LocalizedStringKey {
        switch prompt.caller == nil ? .once : duration {
        case .once: "Allow Once…"
        case .tenMinutes: "Allow for 10 Minutes…"
        case .untilLock: "Allow Until Lock…"
        }
    }

    private var durationDescription: LocalizedStringKey {
        switch duration {
        case .once: "Triwarden asks again the next time this tool starts."
        case .tenMinutes: "Starts from this same terminal window won't ask again for 10 minutes, or until the vault locks. End it early in Access."
        case .untilLock: "Starts from this same terminal window won't ask again until the vault locks. End it early in Access."
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Text(verbatim: value)
                .font(.system(size: 12, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

struct SecretsApprovalPanelContent: View {
    @Bindable var controller: SecretsController
    var body: some View {
        Group {
            if let prompt = controller.pending {
                SecretsApprovalView(prompt: prompt, authenticating: controller.authenticating,
                                    deny: controller.deny, allow: { controller.allow($0) }, initialDuration: initialDuration)
            } else {
                Color.clear
            }
        }
        .modifier(LiveAppearance())
        .modifier(ReducedMotionPolicy())
    }

    private var initialDuration: SecretsGrantDuration {
        #if DEBUG
        controller.selfTestInitialDuration
        #else
        .once
        #endif
    }
}
