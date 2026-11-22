import TriCrypto
import SwiftUI

/// Passwords, passphrases, usernames, PINs and SSH keys. The full page (Sidebar › Generator) shows every option in
/// cards; the compact form is the popover next to a password field (no SSH keys: a key pair is not a field value).
struct GeneratorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case password, passphrase, username, pin, ssh
        var id: Self { self }
        var title: LocalizedStringKey {
            switch self {
            case .password: "Password"; case .passphrase: "Passphrase"; case .username: "Username"
            case .pin: "PIN"; case .ssh: "SSH Key"
            }
        }
    }

    var modes: [Mode] = Mode.allCases
    var compact = false
    /// Shown as a “Use” button (e.g. from the edit sheet).
    var onUse: ((String) -> Void)?

    @Environment(AppModel.self) private var model
    @AppStorage("generatorMode") private var storedMode = Mode.password.rawValue
    @AppStorage("generator") private var storedPassword = Data()
    @AppStorage("passphraseGenerator") private var storedPassphrase = Data()
    @AppStorage("usernameGenerator") private var storedUsername = Data()
    @AppStorage("pinGenerator") private var storedPIN = Data()
    @State private var password = PasswordGenerator()
    @State private var passphrase = PassphraseGenerator()
    @State private var username = UsernameGenerator()
    @State private var pin = PINGenerator()
    /// The SSH key on screen. Memory only, never saved in settings or history: it is dropped when the page changes
    /// mode or closes, unless it was saved to the vault or copied first.
    @State private var sshSeed: Data?
    @State private var sshComment = ""
    @State private var sshPair: SSHKeyPair?
    @State private var copiedPart: String?
    @State private var value = ""
    @State private var loaded = false
    @State private var copied = false

    /// The popover never offers SSH keys.
    private var available: [Mode] { compact ? modes.filter { $0 != .ssh } : modes }

    private var mode: Mode {
        let m = Mode(rawValue: storedMode) ?? .password
        return available.contains(m) ? m : available[0]
    }

    @State private var pageWidth: CGFloat = 1000

    var body: some View {
        Group { if compact { compactBody } else { page } }
            .onAppear(perform: load)
            .onChange(of: password) { save(); regenerate() }
            .onChange(of: passphrase) { save(); regenerate() }
            .onChange(of: username) { save(); regenerate() }
            .onChange(of: pin) { save(); regenerate() }
            .onChange(of: sshComment) { rebuildSSH() }
            .onChange(of: storedMode) { if mode != .ssh { forgetSSH() }; regenerate() }
            .onDisappear(perform: forgetSSH)
            .onChange(of: model.generatorRequest) { regenerate() }
    }

    private var modePicker: some View {
        AppSegmented(options: available.map { ($0, $0.title) },
                     selection: Binding(get: { mode }, set: { storedMode = $0.rawValue }))
            .accessibilityLabel(Text("Type"))
    }

    @ViewBuilder private var options: some View {
        switch mode {
        case .password: passwordOptions
        case .passphrase: passphraseOptions
        case .username: usernameOptions
        case .pin: pinOptions
        case .ssh: sshOptions
        }
    }

    // MARK: Full page

    /// Header with the mode switch, the result as a hero panel, then options and history side by side
    /// (stacked when the window is narrow); the row stretches to fill the window.
    private var page: some View {
        let wide = pageWidth >= 820
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Text("Generator").font(.system(size: 22, weight: .bold)).tracking(-0.3)
                Spacer(minLength: 16)
                modePicker.frame(maxWidth: 520)
            }
            .padding(.bottom, -8) // 10 pt to the result, like the vault page's search row to its list
            if mode == .ssh { sshHero } else { hero }
            (wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(spacing: 16))) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Options").font(.system(size: 13, weight: .semibold))
                    options
                    if wide { Spacer(minLength: 0) }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: wide ? .infinity : nil, alignment: .topLeading)
                .modifier(PanelCard())
                HistorySection()
                    .frame(width: wide ? min(360, pageWidth * 0.36) : nil)
                    .frame(maxWidth: wide ? nil : .infinity, maxHeight: wide ? .infinity : nil)
            }
            .frame(maxHeight: wide ? .infinity : nil, alignment: .top)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Rolling(value.isEmpty ? " " : value, keep: rollKeep) { shown in
                ColoredSecret(value: shown, separator: mode == .passphrase ? passphrase.separator : nil)
            }
                .font(.system(size: value.count > 40 ? 20 : 28, weight: .medium, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .contentTransition(.opacity)
                .accessibilityLabel(Text(verbatim: value))
                .accessibilityIdentifier("generatedValue")
            HStack(spacing: 12) {
                if mode == .pin {
                    pinStats.font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                } else if mode != .username {
                    let bits = mode == .password ? password.entropyBits : passphrase.entropyBits
                    StrengthMeter(bits: bits).fixedSize()
                    statsText(bits: bits)
                } else if value.isEmpty {
                    Text(username.kind == .plusAddressed ? "Enter your email address below." : "Enter your catch-all domain below.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button { regenerate() } label: { Label("Regenerate", systemImage: "arrow.clockwise") }
                    .buttonStyle(.appSecondary)
                    .keyboardShortcut("r", modifiers: .command)
                Button { copy() } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.appPrimary)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(value.isEmpty)
            }
        }
        .padding(24)
        .modifier(PanelCard())
    }

    /// A PIN is only as safe as the lock in front of it, so say that rather than show a "weak" meter.
    private var pinStats: Text {
        Text("\(value.count) digits") + Text(verbatim: " · ") + Text("Best where wrong guesses lock you out")
    }

    /// The key pair: the public half and its fingerprint in full, the private half kept off screen. Saving opens a new
    /// SSH key item with all three filled in.
    private var sshHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let pair = sshPair {
                VStack(alignment: .leading, spacing: 6) {
                    OptionLabel("Public key")
                    Text(verbatim: pair.publicKey)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .textSelection(.enabled)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("generatedPublicKey")
                }
                VStack(alignment: .leading, spacing: 6) {
                    OptionLabel("Fingerprint")
                    Text(verbatim: pair.fingerprint)
                        .font(.system(size: 13, design: .monospaced)).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(1).truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    Image(systemName: "lock").font(.system(size: 11)).accessibilityHidden(true)
                    Text("The private key stays hidden. It is forgotten when you leave this page unless you save it to your vault.")
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { sshButtons(spaced: true) }
                VStack(alignment: .leading, spacing: 10) { sshButtons(spaced: false) }
            }
        }
        .padding(24)
        .modifier(PanelCard())
    }

    @ViewBuilder private func sshButtons(spaced: Bool) -> some View {
        Button { regenerate() } label: { Label("New Key", systemImage: "arrow.clockwise") }
            .buttonStyle(.appSecondary)
            .keyboardShortcut("r", modifiers: .command)
        if spaced { Spacer(minLength: 12) }
        Button { copySSH(\.privateKey, part: "private", label: String(localized: "Private key")) } label: {
            Label(copiedPart == "private" ? "Copied" : "Copy Private Key", systemImage: copiedPart == "private" ? "checkmark" : "key")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.appSecondary)
        .disabled(sshPair == nil)
        Button { copySSH(\.publicKey, part: "public", label: String(localized: "Public key")) } label: {
            Label(copiedPart == "public" ? "Copied" : "Copy Public Key", systemImage: copiedPart == "public" ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.appSecondary)
        .keyboardShortcut("c", modifiers: [.command, .shift])
        .disabled(sshPair == nil)
        Button { saveSSHKey() } label: { Label("Save as SSH Key…", systemImage: "tray.and.arrow.down") }
            .buttonStyle(.appPrimary)
            .disabled(sshPair == nil || !model.isUnlocked)
            .accessibilityIdentifier("saveGeneratedSSHKey")
    }

    /// "20 characters · centuries to crack" — offline guessing at 10 billion tries a second.
    private func statsText(bits: Double) -> some View {
        let count = mode == .password ? Text("\(value.count) characters") : Text("\(passphrase.words) words")
        return (count + Text(verbatim: " · ") + Text(Self.crackTime(bits: bits)))
            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
    }

    static func crackTime(bits: Double) -> LocalizedStringKey {
        let seconds = pow(2, bits - 1) / 1e10
        switch seconds {
        case ..<1: return "cracked instantly"
        case ..<3600: return "minutes to crack"
        case ..<86_400: return "hours to crack"
        case ..<(86_400 * 365): return "days to crack"
        case ..<(86_400 * 365 * 1000): return "years to crack"
        default: return "centuries to crack"
        }
    }

    // MARK: Compact (popover)

    /// "Use Password" / "Use Passphrase" / "Use Username" — the button must name what it inserts, and the compact
    /// form offers all three (a passphrase is not a password).
    private var useTitle: LocalizedStringKey {
        switch mode {
        case .password: "Use Password"
        case .passphrase: "Use Passphrase"
        case .username: "Use Username"
        case .pin: "Use PIN"
        case .ssh: "Save as SSH Key…"
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            if available.count > 1 { modePicker }
            output
            options

            if let onUse {
                // Single CTA, centered: a trailing pill sat under the popover arrow
                // (every compact presentation uses arrowEdge: .trailing) and the
                // "Use Password" label was clipped on the right.
                Button(useTitle) { remember(); onUse(value) }
                    .buttonStyle(.appPrimary)
                    .disabled(value.isEmpty)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: Output

    private var output: some View {
        VStack(alignment: .leading, spacing: 10) {
            Rolling(value, keep: rollKeep) { shown in
                ColoredSecret(value: shown, separator: mode == .passphrase ? passphrase.separator : nil)
            }
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
                .accessibilityLabel(Text(verbatim: value))
            HStack(spacing: 6) {
                if mode == .pin {
                    Text("\(value.count) digits").font(.caption).foregroundStyle(.secondary)
                } else if mode != .username {
                    StrengthMeter(bits: mode == .password ? password.entropyBits : passphrase.entropyBits)
                } else if value.isEmpty {
                    Text(username.kind == .plusAddressed ? "Enter your email address below." : "Enter your catch-all domain below.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                iconButton("arrow.clockwise", help: "Regenerate") { regenerate() }
                    .keyboardShortcut("r", modifiers: .command)
                iconButton(copied ? "checkmark" : "doc.on.doc", help: "Copy") { copy() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
        .padding(12)
        .background(Color.panelStrong, in: .rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.panelEdge))
    }

    private func iconButton(_ symbol: String, help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.06), in: .circle)
                .contentShape(.circle)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .help(Text(help))
        .accessibilityLabel(Text(help))
    }

    // MARK: Options

    @ViewBuilder private var passwordOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            NumberRow(label: "Length", value: $password.length, range: PasswordGenerator.lengthRange,
                      hint: "Value must be between 5 and 128.", slider: true)
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 8) {
                OptionLabel("Include")
                HStack(spacing: 8) {
                    ToggleChip(title: "A-Z", isOn: $password.uppercase)
                    ToggleChip(title: "a-z", isOn: $password.lowercase)
                    ToggleChip(title: "0-9", isOn: $password.digits)
                    ToggleChip(title: "!@#$%^&*", isOn: $password.symbols)
                }
            }
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    OptionLabel("Minimum numbers")
                    NumberStepper(value: $password.minNumbers, range: 0...9)
                }
                .disabled(!password.digits).opacity(password.digits ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 8) {
                    OptionLabel("Minimum special")
                    NumberStepper(value: $password.minSpecial, range: 0...9)
                }
                .disabled(!password.symbols).opacity(password.symbols ? 1 : 0.5)
                Spacer()
            }
            Divider().opacity(0.4)
            SwitchRow("Avoid ambiguous characters", isOn: $password.avoidAmbiguous)
        }
    }

    @ViewBuilder private var passphraseOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            NumberRow(label: "Number of words", value: $passphrase.words, range: PassphraseGenerator.wordRange,
                      hint: "Value must be between 3 and 20. Use 6 words or more to generate a strong passphrase.", slider: true)
            Divider().opacity(0.4)
            HStack {
                OptionLabel("Word separator")
                Spacer()
                TextField("", text: $passphrase.separator)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .frame(width: 56, height: 32)
                    .background(Color.primary.opacity(0.05), in: .capsule)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
                    .onChange(of: passphrase.separator) { _, new in if new.count > 3 { passphrase.separator = String(new.prefix(3)) } }
                    .accessibilityLabel(Text("Word separator"))
            }
            SwitchRow("Capitalize", isOn: $passphrase.capitalize)
            SwitchRow("Include number", isOn: $passphrase.includeNumber)
        }
    }

    @ViewBuilder private var usernameOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            AppSegmented(options: [(UsernameGenerator.Kind.randomWord, "Random word"),
                                   (.plusAddressed, "Plus-addressed email"), (.catchAll, "Catch-all email")],
                         selection: $username.kind)
                .accessibilityLabel(Text("Username"))
            switch username.kind {
            case .randomWord:
                SwitchRow("Capitalize", isOn: $username.capitalize)
                SwitchRow("Include number", isOn: $username.includeNumber)
            case .plusAddressed:
                TextField("Email", text: $username.email, prompt: Text(verbatim: "you@example.com")).textFieldStyle(SoftFieldStyle())
                Text("Adds a random tag, e.g. you+k3x9q2ma@example.com, so you can tell who shared your address.")
                    .font(.caption).foregroundStyle(.secondary)
            case .catchAll:
                TextField("Domain", text: $username.domain, prompt: Text(verbatim: "example.com")).textFieldStyle(SoftFieldStyle())
                Text("A random address at a domain that accepts any mailbox.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var pinOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            NumberRow(label: "Length", value: $pin.length, range: PINGenerator.lengthRange,
                      hint: "Value must be between 4 and 16. Most cards and phones use 4 to 6 digits.", slider: true)
            Divider().opacity(0.4)
            SwitchRow("Avoid easy patterns", isOn: $pin.avoidPatterns)
            Text("Skips runs people try first, such as 123, 987 or 777.").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var sshOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                OptionLabel("Key type")
                Text(verbatim: "Ed25519")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(Color.primary.opacity(0.05), in: .capsule)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.10)))
                Text("Short, fast and accepted by GitHub, GitLab and OpenSSH servers.").font(.caption).foregroundStyle(.secondary)
            }
            Divider().opacity(0.4)
            VStack(alignment: .leading, spacing: 8) {
                OptionLabel("Comment")
                TextField("Comment", text: $sshComment, prompt: Text(verbatim: "you@laptop")).textFieldStyle(SoftFieldStyle())
                    .accessibilityIdentifier("sshKeyComment")
                Text("Added to the end of the public key so you can tell your keys apart. Changing it keeps the same key.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: State

    private func load() {
        guard !loaded else { return }
        if let p = try? JSONDecoder().decode(PasswordGenerator.self, from: storedPassword) { password = p }
        if let p = try? JSONDecoder().decode(PassphraseGenerator.self, from: storedPassphrase) { passphrase = p }
        if let u = try? JSONDecoder().decode(UsernameGenerator.self, from: storedUsername) { username = u }
        if let p = try? JSONDecoder().decode(PINGenerator.self, from: storedPIN) { pin = p }
        if username.email.isEmpty { username.email = model.sessions.first?.account.email ?? "" }
        loaded = true
        regenerate()
    }

    private func save() {
        storedPassword = (try? JSONEncoder().encode(password)) ?? storedPassword
        storedPassphrase = (try? JSONEncoder().encode(passphrase)) ?? storedPassphrase
        storedUsername = (try? JSONEncoder().encode(username)) ?? storedUsername
        storedPIN = (try? JSONEncoder().encode(pin)) ?? storedPIN
    }

    /// What stays still while a new value rolls in: spaces, and a passphrase's separators (so the words keep their shape).
    private var rollKeep: Set<Character> { mode == .passphrase ? Set(" " + passphrase.separator) : [" "] }

    private func regenerate() {
        withAnimation(.snappy(duration: 0.2)) {
            switch mode {
            case .password: value = password.generate()
            case .passphrase: value = passphrase.generate()
            case .username: value = username.generate() ?? ""
            case .pin: value = pin.generate()
            case .ssh:
                sshSeed = SSHKeyPair.newEd25519Seed()
                rebuildSSH()
            }
        }
    }

    /// The same key with the current comment.
    private func rebuildSSH() {
        guard let sshSeed else { return }
        sshPair = try? SSHKeyPair.ed25519(seed: sshSeed, comment: sshComment.trimmingCharacters(in: .whitespacesAndNewlines))
        value = sshPair?.publicKey ?? ""
    }

    private func forgetSSH() {
        sshSeed = nil
        sshPair = nil
        if mode == .ssh { value = "" }
    }

    private func copySSH(_ part: KeyPath<SSHKeyPair, String>, part name: String, label: String) {
        guard let pair = sshPair else { return }
        model.copy(pair[keyPath: part], label: label)
        withAnimation(.snappy) { copiedPart = name }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.snappy) { if copiedPart == name { copiedPart = nil } }
        }
    }

    /// Opens a new SSH key item with this key filled in; leaving the page then drops the copy held here.
    private func saveSSHKey() {
        guard let pair = sshPair else { return }
        let comment = sshComment.trimmingCharacters(in: .whitespacesAndNewlines)
        model.beginEditing(EditRequest(mode: .create(.sshKey), prefill: EditItemSheet.Prefill(
            name: comment.isEmpty ? String(localized: "SSH Key") : comment,
            properties: ["privateKey": pair.privateKey, "publicKey": pair.publicKey, "keyFingerprint": pair.fingerprint])))
    }

    private func copy() {
        guard !value.isEmpty else { return }
        model.copy(value, label: Self.copyLabel(kind: mode.rawValue))
        remember()
        withAnimation(.snappy) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.snappy) { copied = false }
        }
    }

    /// SSH keys are never kept in the history.
    private func remember() { if mode != .ssh { model.rememberGenerated(value, kind: mode.rawValue) } }

    static func copyLabel(kind: String) -> String {
        switch kind {
        case Mode.username.rawValue: String(localized: "Username")
        case Mode.passphrase.rawValue: String(localized: "Passphrase")
        case Mode.pin.rawValue: String(localized: "PIN")
        default: String(localized: "Password")
        }
    }
}

/// Digits in brand blue, symbols (and passphrase separators) in coral, letters in the text colour.
/// Glyphs wrap at the container edge (not at letter-runs), so a 128-character password fills each line.
struct ColoredSecret: View {
    let value: String
    var separator: String?

    var body: some View {
        GlyphWrap {
            ForEach(Array(value.enumerated()), id: \.offset) { _, ch in
                Text(verbatim: String(ch)).foregroundStyle(Self.color(ch, separator: separator))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: value))
    }

    static func color(_ ch: Character, separator: String?) -> Color {
        if ch.isNumber { return .brand }
        if let separator, separator.contains(ch) { return Color(red: 0.90, green: 0.32, blue: 0.36) }
        if !ch.isLetter { return Color(red: 0.90, green: 0.32, blue: 0.36) }
        return .primary
    }
}

/// Places one glyph after another and wraps at `proposal.width`, like `lineBreakMode = .byCharWrapping`.
private struct GlyphWrap: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { y += row; x = 0; row = 0 }
            x += size.width
            row = max(row, size.height)
            widest = max(widest, x)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { y += row; x = bounds.minX; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width
            row = max(row, size.height)
        }
    }
}

/// A labelled number: brand slider plus the shared − / + stepper, clamped to its range.
private struct NumberRow: View {
    let label: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    var hint: LocalizedStringKey?
    var slider = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OptionLabel(label)
            HStack(spacing: 14) {
                if slider {
                    Slider(value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                           in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                        .labelsHidden()
                        .tint(.controlTint)
                }
                NumberStepper(value: $value, range: range)
            }
            if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct OptionLabel: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View { Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
}

/// A label with a small switch on the right.
private struct SwitchRow: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool
    init(_ title: LocalizedStringKey, isOn: Binding<Bool>) { self.title = title; _isOn = isOn }
    var body: some View {
        Toggle(isOn: $isOn) { Text(title).font(.system(size: 13)) }
            .toggleStyle(.trailingSwitch)
    }
}

private struct PanelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))
    }
}

/// Recently copied or used values. In memory only; cleared when the vault locks.
private struct HistorySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("History").font(.system(size: 13, weight: .semibold))
                if !model.generatorHistory.isEmpty {
                    Text(verbatim: "\(model.generatorHistory.count)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.generatorHistory.isEmpty {
                    Button("Clear") {
                        model.confirm(String(localized: "Clear generator history?"),
                                      message: String(localized: "The values listed here are forgotten. Items you saved are not affected."),
                                      action: String(localized: "Clear History")) { model.generatorHistory.removeAll() }
                    }
                    .buttonStyle(.appSecondarySmall)
                }
            }
            .padding(.horizontal, 20).frame(height: 52)

            if model.generatorHistory.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 22)).foregroundStyle(.tertiary)
                    Text("Nothing yet").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                    Text("Values you copy or use appear here until the vault locks.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.generatorHistory) { entry in HistoryRow(entry: entry) }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 8)
                }
                .thinScroller()
                .frame(minHeight: 120)
            }
        }
        .modifier(PanelCard())
    }
}

private struct HistoryRow: View {
    @Environment(AppModel.self) private var model
    let entry: AppModel.GeneratedEntry
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.kind == "username" ? "person" : entry.kind == "passphrase" ? "text.quote"
                  : entry.kind == "pin" ? "number" : "key")
                .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: entry.value).font(.system(size: 13, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 4) {
                    if let site = entry.site {
                        Text(verbatim: site).lineLimit(1).truncationMode(.middle)
                        Text(verbatim: "·")
                    }
                    Text(entry.date, format: .relative(presentation: .named))
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                model.copy(entry.value, label: GeneratorView.copyLabel(kind: entry.kind))
            } label: {
                Image(systemName: "doc.on.doc").font(.system(size: 12)).frame(width: 26, height: 26).contentShape(.rect)
            }
            .buttonStyle(HeaderIconStyle())
            .opacity(hovering ? 1 : 0.5)
            .help(Text("Copy"))
            .accessibilityLabel(Text("Copy"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color.primary.opacity(hovering ? 0.05 : 0), in: .rect(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
    }
}
