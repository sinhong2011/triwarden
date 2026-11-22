import SwiftUI
import VaultwardenAPI

/// Local password health checks; breach lookups only on request (k-anonymity, see `PwnedPasswords`).
struct WatchtowerReport {
    enum Issue: CaseIterable, Hashable {
        case breached, reused, weak, insecure, twoFactor, cardExpiring, duplicate, oldPassword

        /// Advice, not a problem: doesn't count against the score.
        var isAdvisory: Bool { [.twoFactor, .cardExpiring, .duplicate, .oldPassword].contains(self) }

        var title: LocalizedStringKey {
            switch self {
            case .breached: "Exposed in data breaches"
            case .reused: "Reused passwords"
            case .weak: "Weak passwords"
            case .insecure: "Unsecured websites"
            case .twoFactor: "Two-step login available"
            case .cardExpiring: "Cards expiring"
            case .duplicate: "Duplicate logins"
            case .oldPassword: "Passwords not changed in years"
            }
        }
        var symbol: String {
            switch self {
            case .breached: "exclamationmark.shield"
            case .reused: "arrow.triangle.2.circlepath"
            case .weak: "lock.open"
            case .insecure: "network.slash"
            case .twoFactor: "person.badge.shield.checkmark"
            case .cardExpiring: "creditcard"
            case .duplicate: "square.on.square"
            case .oldPassword: "calendar.badge.clock"
            }
        }
        var tint: Color {
            switch self {
            case .breached: .red
            case .reused, .weak: .orange
            case .insecure: .yellow
            case .twoFactor: .blue
            case .cardExpiring: .orange
            case .duplicate, .oldPassword: .secondary
            }
        }
        /// The mark at the end of an item's row.
        var rowSymbol: String {
            switch self {
            case .breached: "exclamationmark.shield.fill"
            case .reused: "arrow.triangle.2.circlepath"
            case .weak: "exclamationmark.triangle.fill"
            case .insecure: "lock.open.fill"
            default: symbol
            }
        }
        /// The word on the list's chip.
        var shortLabel: LocalizedStringKey {
            switch self {
            case .breached: "Breached"
            case .reused: "Reused"
            case .weak: "Weak"
            case .insecure: "Unencrypted"
            default: title
            }
        }
        /// What that mark says, for its tooltip.
        var rowLabel: LocalizedStringKey {
            switch self {
            case .breached: "Password found in a data breach"
            case .reused: "Password used on other items too"
            case .weak: "Weak password"
            case .insecure: "Saved for an http:// site, sent unencrypted"
            default: title
            }
        }
        var advice: LocalizedStringKey {
            switch self {
            case .breached: "These passwords appear in known breaches. Change them on each site."
            case .reused: "One leak exposes every site that shares a password. Give each its own."
            case .weak: "Short or simple passwords are easy to guess. Generate a longer one."
            case .insecure: "These sites are saved with http://, so the password travels unencrypted."
            case .twoFactor: "These sites offer one-time codes. Turn two-step login on there, then save the code here."
            case .cardExpiring: "Expired, or expiring in the next two months. Put the new card's dates in once it arrives."
            case .duplicate: "The same username for the same site, saved more than once. Keep the one that's right and move the rest to Trash."
            case .oldPassword: "Unchanged for three years or more. No need to change a strong, unique one; worth it for an account that matters."
            }
        }
    }

    let logins: [VaultItem]
    let issues: [Issue: [VaultItem]]
    /// Logins that share a password, grouped; `issues[.reused]` lists the same items in this order.
    let reuseGroups: [ReuseGroup]

    /// Logins in one vault account with the same password. The password itself stays out of it: the group is known
    /// by an opaque, stable ID (its lowest item ID), and nothing here is shown or kept beyond the report.
    struct ReuseGroup: Identifiable, Equatable {
        let id: String
        let items: [VaultItem]
        static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.items.map(\.id) == b.items.map(\.id) }
    }

    /// `twoFactor`: sites that offer one-time codes (2fa.directory), by domain, with their setup guide.
    init(items: [VaultItem], breaches: [String: Int]?, twoFactor: [String: URL] = [:]) {
        logins = items.filter { !$0.isDeleted && $0.kind == .login && $0.password != nil }
        var issues: [Issue: [VaultItem]] = [:]
        for item in logins {
            guard let pw = item.password else { continue }
            if let n = breaches?[item.id], n > 0 { issues[.breached, default: []].append(item) }
            if Self.isWeak(pw) { issues[.weak, default: []].append(item) }
            if item.websites.contains(where: Self.isInsecure) { issues[.insecure, default: []].append(item) }
            if item.totp == nil, !item.hasPasskey, let host = item.host, Self.guide(for: host, in: twoFactor) != nil {
                issues[.twoFactor, default: []].append(item)
            }
        }
        let cards = items.filter { !$0.isDeleted && !$0.isArchived && $0.kind == .card }
        let expiring = cards.filter { $0.cardExpiry.map { $0 < Self.expiryHorizon } ?? false }
            .sorted { ($0.cardExpiry ?? .distantPast) < ($1.cardExpiry ?? .distantPast) }
        if !expiring.isEmpty { issues[.cardExpiring] = expiring }
        let old = logins.filter { $0.passwordSince.map { $0 < Self.oldPasswordDate } ?? false }
            .sorted { ($0.passwordSince ?? .distantPast) < ($1.passwordSince ?? .distantPast) }
        if !old.isEmpty { issues[.oldPassword] = old }
        let duplicates = Self.duplicateGroups(logins).flatMap { $0 }
        if !duplicates.isEmpty { issues[.duplicate] = duplicates }
        reuseGroups = Self.reuseGroups(logins)
        let reused = reuseGroups.flatMap(\.items)
        if !reused.isEmpty { issues[.reused] = reused }
        self.issues = issues
    }

    /// Groups the logins that share a password within one account (as the sync counts reuse), biggest group first,
    /// each in name order. A group that is only copies of one login is left to Duplicate logins. One pass over the
    /// logins; the passwords are only dictionary keys here.
    static func reuseGroups(_ logins: [VaultItem]) -> [ReuseGroup] {
        var byPassword: [String: [VaultItem]] = [:]
        for item in logins {
            guard let pw = item.password, !pw.isEmpty else { continue }
            byPassword[item.accountId + "\u{1F}" + pw, default: []].append(item)
        }
        return byPassword.values.compactMap { group -> ReuseGroup? in
            guard group.count > 1 else { return nil }
            // One login saved more than once isn't reuse to fix here: Duplicate logins keeps one and trashes the rest.
            if let key = duplicateKey(group[0]), group.allSatisfy({ duplicateKey($0) == key }) { return nil }
            let sorted = group.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return ReuseGroup(id: group.map(\.id).min()!, items: sorted)
        }
        .sorted { a, b in
            a.items.count != b.items.count ? a.items.count > b.items.count
                : a.items[0].name.localizedStandardCompare(b.items[0].name) == .orderedAscending
        }
    }

    /// Cards that expire before this are worth a word.
    static var expiryHorizon: Date { Calendar.current.date(byAdding: .day, value: 60, to: .now) ?? .now }
    static var oldPasswordDate: Date { Calendar.current.date(byAdding: .year, value: -3, to: .now) ?? .distantPast }

    /// Logins saved more than once: the same site and username in the same vault, newest first in each group.
    static func duplicateGroups(_ logins: [VaultItem]) -> [[VaultItem]] {
        let keyed = Dictionary(grouping: logins.filter { !$0.isArchived }, by: duplicateKey)
        return keyed.compactMap { key, group in
            key == nil || group.count < 2 ? nil
                : group.sorted { ($0.revised ?? .distantPast) > ($1.revised ?? .distantPast) }
        }
        .sorted { $0[0].name.localizedStandardCompare($1[0].name) == .orderedAscending }
    }

    /// The same login, in the same vault: its site (without www.) and username. Nil without both.
    static func duplicateKey(_ item: VaultItem) -> String? {
        guard let host = item.host?.lowercased(), let user = item.username?.lowercased(), !user.isEmpty else { return nil }
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return [item.organizationId ?? item.accountId, site, user].joined(separator: "\u{1F}")
    }

    var problemCount: Int { Set(issues.filter { !$0.key.isAdvisory }.values.flatMap { $0.map(\.id) }).count }

    /// The same count as a report's `problemCount`, without building the report (its lists, cards, duplicate groups
    /// and password ages): the sidebar's badge asks for it on every redraw. The problems are the issues that aren't
    /// advisory (breached, reused, weak, insecure), counted once per item.
    static func countProblems(in items: [VaultItem], breaches: [String: Int]?) -> Int {
        var ids = Set<String>()
        var sharing: [VaultItem] = []
        for item in items where !item.isDeleted && item.kind == .login {
            guard let pw = item.password else { continue }
            if (breaches?[item.id] ?? 0) > 0 || Self.isWeak(pw) || item.websites.contains(where: Self.isInsecure) {
                ids.insert(item.id)
            }
            if item.reuseCount > 0 { sharing.append(item) } // all of them: a weak one's partner still counts
        }
        // Reuse as the report groups it (copies of one login don't count), over only the logins that share a password.
        for group in reuseGroups(sharing) { ids.formUnion(group.items.map(\.id)) }
        return ids.count
    }

    /// The setup guide for a host or the domain it falls under.
    static func guide(for host: String, in directory: [String: URL]) -> URL? {
        var parts = host.lowercased().split(separator: ".")
        while parts.count >= 2 {
            if let url = directory[parts.joined(separator: ".")] { return url }
            parts.removeFirst()
        }
        return nil
    }

    /// Share of logins with no issues, 0…1.
    var score: Double { logins.isEmpty ? 1 : 1 - Double(problemCount) / Double(logins.count) }

    static func isWeak(_ pw: String) -> Bool {
        let classes = [pw.contains(where: \.isLowercase), pw.contains(where: \.isUppercase),
                       pw.contains(where: \.isNumber), pw.contains { !$0.isLetter && !$0.isNumber }].filter { $0 }.count
        return pw.count < 10 || (pw.count < 14 && classes < 3)
    }

    /// http:// on a public host (local and private-network addresses are fine).
    static func isInsecure(_ uri: String) -> Bool {
        guard let url = URL(string: uri), url.scheme?.lowercased() == "http", let host = url.host()?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".lan") || host.hasSuffix(".home.arpa")
            || host.hasSuffix(".internal") || !host.contains(".") { return false }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4 {
            switch (octets[0], octets[1]) {
            case (10, _), (127, _), (192, 168), (169, 254): return false
            case (172, 16...31): return false
            default: return true
            }
        }
        return true
    }
}

struct WatchtowerView: View {
    @Environment(AppModel.self) private var model
    var onOpen: (VaultItem) -> Void
    @State private var directory: [String: URL] = [:]
    /// The score as drawn: it sweeps up from 0 when the page opens, then follows the real one.
    @State private var animatedScore: Double?
    @State private var allClear = 0
    /// The row pointed out by an item's "Show in Watchtower".
    @State private var highlighted: String?
    /// Every reused-password group, not just the first few.
    @State private var showAllReuse = false

    var body: some View {
        let report = WatchtowerReport(items: model.vaultItems, breaches: model.breachCounts, twoFactor: directory)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(report)
                ForEach(WatchtowerReport.Issue.allCases.filter { model.watchtowerIssueFilter == nil || $0 == model.watchtowerIssueFilter }, id: \.self) { issue in
                    if issue == .reused, !report.reuseGroups.isEmpty || !model.reuseFollowUps.isEmpty {
                        ReusedCard(groups: report.reuseGroups, showAll: $showAllReuse, highlighted: highlighted, onOpen: onOpen)
                    } else if let items = report.issues[issue], !items.isEmpty {
                        IssueCard(issue: issue, items: items, directory: directory, highlighted: highlighted, onOpen: onOpen)
                    }
                }
                if let filter = model.watchtowerIssueFilter {
                    HStack {
                        Text(filter.title).font(.headline)
                        Spacer()
                        Button("Show All") { model.watchtowerIssueFilter = nil }
                    }
                    if report.issues[filter, default: []].isEmpty {
                        Text(filter == .breached && model.breachCounts == nil ? "Run Checks to check for breached passwords."
                             : filter == .reused ? "No reused passwords. Every login has its own." : "No issues found.")
                            .foregroundStyle(.secondary)
                    }
                }
                if report.problemCount == 0 && model.watchtowerIssueFilter == nil {
                    ContentUnavailableView {
                        Label("Looking good", systemImage: "checkmark.shield")
                            .symbolEffect(.bounce.up, options: .speed(0.9), value: allClear)
                    } description: {
                        Text(model.breachCounts == nil
                                               ? "No weak, reused or unsecured passwords. Check for breaches to be sure."
                                               : "No issues found.")
                    }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                        .onAppear { allClear += 1 }
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 24) // from the top, like the vault page's search row
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.45, bounce: 0.2), value: report.problemCount)
        }
        .thinScroller() // the app's slim scroller, not the system's wide track
        .task { directory = await TwoFactorDirectory.load() }
        .onAppear {
            // The ring sweeps up to the score and the number counts with it.
            animatedScore = 0
            withAnimation(.spring(duration: 1.1, bounce: 0.1).delay(0.15)) { animatedScore = report.score }
        }
        .onChange(of: report.score) { _, new in withAnimation(.spring(duration: 0.7, bounce: 0.15)) { animatedScore = new } }
        // Opened from an item's Watchtower row: to its issue, highlighted for a moment.
        .onChange(of: model.watchtowerFocus, initial: true) { _, id in
            guard let id, let item = model.items.first(where: { $0.id == id }) else { return }
            model.watchtowerFocus = nil
            let listed = { (issue: WatchtowerReport.Issue) in report.issues[issue]?.contains(where: { $0.id == id }) == true }
            let issue = item.passwordIssue(breaches: model.breachCounts).flatMap { listed($0) ? $0 : nil }
                ?? WatchtowerReport.Issue.allCases.first(where: listed)
            guard let issue else { return }
            if issue == .reused { showAllReuse = true } // its group may be past the first few
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250)) // after the page has laid out
                withAnimation(.smooth(duration: 0.45)) { proxy.scrollTo(IssueCard.rowID(issue, id), anchor: .center) }
                withAnimation(.easeOut(duration: 0.2)) { highlighted = IssueCard.rowID(issue, id) }
                try? await Task.sleep(for: .seconds(1.8))
                withAnimation(.easeOut(duration: 0.6)) { highlighted = nil }
            }
        }
        }
    }

    private func header(_ report: WatchtowerReport) -> some View {
        let shownScore = Motion.plays ? animatedScore ?? 0 : report.score
        return HStack(spacing: 22) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 9)
                Circle().trim(from: 0, to: shownScore)
                    .stroke(shownScore > 0.9 ? Color.green : shownScore > 0.7 ? Color.orange : Color.red,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    CountingNumber(value: shownScore * 100).font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("score").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 96, height: 96)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("score"))
            .accessibilityValue(Text(verbatim: "\(Int((report.score * 100).rounded()))"))

            VStack(alignment: .leading, spacing: 6) {
                Text("Watchtower").font(.system(size: 24, weight: .bold))
                Text("\(report.problemCount) of \(report.logins.count) logins need attention.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        Task { await model.checkBreaches() }
                    } label: {
                        HStack(spacing: 6) {
                            if model.isCheckingBreaches { ProgressView().controlSize(.small) }
                            Text(model.breachCounts == nil ? "Check for breaches" : "Check again")
                        }
                    }
                    .buttonStyle(.appPrimarySmall)
                    .disabled(model.isCheckingBreaches || report.logins.isEmpty)
                    if let checked = model.breachesCheckedAt {
                        Text("Checked \(checked, format: .relative(presentation: .named))").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
                Text("Sends only the first 5 characters of each password's SHA-1 hash to Have I Been Pwned. Passwords never leave this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.panelStrong, in: .rect(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelEdge))
    }
}

private struct IssueCard: View {
    @Environment(AppModel.self) private var model
    let issue: WatchtowerReport.Issue
    let items: [VaultItem]
    var directory: [String: URL] = [:]
    var highlighted: String?
    var onOpen: (VaultItem) -> Void

    static func rowID(_ issue: WatchtowerReport.Issue, _ itemID: String) -> String { "\(issue)-\(itemID)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: issue.symbol).foregroundStyle(issue.tint).font(.system(size: 15, weight: .semibold))
                Text(issue.title).font(.system(size: 15, weight: .semibold))
                Text(verbatim: "\(items.count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(issue.tint.opacity(0.15), in: .capsule)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14)
            Text(issue.advice).font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
            ForEach(items) { item in
                Divider().padding(.leading, 16)
                HStack(spacing: 12) {
                    ItemIcon(item: item, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(verbatim: detail(item)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if issue == .twoFactor, let host = item.host, let guide = WatchtowerReport.guide(for: host, in: directory) {
                        Button("How to Turn On") { NSWorkspace.shared.open(guide) }
                            .buttonStyle(.appSecondarySmall)
                        Button("Add Code") { model.guarded(item) { model.beginEditing(EditRequest(mode: .edit(item))) } }
                            .buttonStyle(.appSecondarySmall)
                    } else if issue == .cardExpiring {
                        Button("Update Card") { model.guarded(item) { model.beginEditing(EditRequest(mode: .edit(item))) } }
                            .buttonStyle(.appSecondarySmall)
                    } else if issue == .duplicate {
                        Button("Move to Trash…") { model.confirmTrash(item) }
                            .buttonStyle(.appSecondarySmall)
                    } else if let host = item.host, !host.isEmpty, [.breached, .reused, .weak, .oldPassword].contains(issue) {
                        // Change it where it lives, then save the new one here.
                        ChangeOnSiteButton(host: host)
                        Button { model.guarded(item) { model.beginEditing(EditRequest(mode: .edit(item))) } } label: {
                            Image(systemName: "pencil").accessibilityLabel(Text("Edit"))
                        }
                        .buttonStyle(.borderless)
                        .help(Text("Edit the item to save the new password"))
                    } else {
                        Button("Change Password") { model.guarded(item) { model.beginEditing(EditRequest(mode: .edit(item))) } }
                            .buttonStyle(.appSecondarySmall)
                    }
                    Button { onOpen(item) } label: { Image(systemName: "arrow.right.circle").accessibilityLabel(Text("Open item")) }
                        .buttonStyle(.borderless)
                        .help(Text("Show item"))
                }
                .padding(.horizontal, 16).frame(minHeight: 48)
                .background(Color.primary.opacity(highlighted == Self.rowID(issue, item.id) ? 0.07 : 0))
                .id(Self.rowID(issue, item.id))
            }
        }
        .background(Color.panelStrong, in: .rect(cornerRadius: 16, style: .continuous))
        .clipShape(.rect(cornerRadius: 16, style: .continuous)) // a highlighted last row keeps the corners
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.panelEdge))
    }

    private func detail(_ item: VaultItem) -> String {
        switch issue {
        case .breached: String(localized: "Seen \(model.breachCounts?[item.id] ?? 0) times")
        case .reused: String(AttributedString(localized: "Shared with ^[\(item.reuseCount) other item](inflect: true)").characters)
        case .weak: [item.username, item.host].compactMap { $0 }.joined(separator: " · ")
        case .insecure: item.uri ?? ""
        case .twoFactor: [item.username, item.host].compactMap { $0 }.joined(separator: " · ")
        case .cardExpiring:
            [item.username, item.cardExpiryText].compactMap { $0 }.joined(separator: " · ")
        case .duplicate:
            [item.username, item.host, item.revised.map { String(localized: "edited \($0.formatted(.relative(presentation: .named)))") }]
                .compactMap { $0 }.joined(separator: " · ")
        case .oldPassword:
            [item.host, item.passwordSince.map { String(localized: "set \($0.formatted(.relative(presentation: .named)))") }]
                .compactMap { $0 }.joined(separator: " · ")
        }
    }
}

/// Reused passwords as a guided cleanup. Each group is the logins sharing one password: pick the one that keeps it,
/// then give the others new passwords (here, then on their sites). The shared password is never shown, and nothing
/// changes a password without its editor: the only bulk action is moving picked logins to Trash, after asking.
private struct ReusedCard: View {
    @Environment(AppModel.self) private var model
    let groups: [WatchtowerReport.ReuseGroup]
    @Binding var showAll: Bool
    var highlighted: String?
    var onOpen: (VaultItem) -> Void
    /// The group picking logins to move to Trash, and what's picked in it.
    @State private var selectingGroup: String?
    @State private var selection: Set<String> = []

    /// Groups shown before "Show All"; a large vault can have dozens.
    static let firstGroups = 8

    var body: some View {
        let shown = showAll ? groups : Array(groups.prefix(Self.firstGroups))
        let count = groups.reduce(0) { $0 + $1.items.count }
        let pending = followUps
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: WatchtowerReport.Issue.reused.symbol).foregroundStyle(WatchtowerReport.Issue.reused.tint)
                    .font(.system(size: 15, weight: .semibold))
                Text(WatchtowerReport.Issue.reused.title).font(.system(size: 15, weight: .semibold))
                if count > 0 {
                    Text(verbatim: "\(count)").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(WatchtowerReport.Issue.reused.tint.opacity(0.15), in: .capsule)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 14)
            Text(groups.isEmpty ? "No reused passwords left. Put the new ones on each site below."
                 : "One leak exposes every site that shares a password. In each group, keep one and give the others new passwords.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 10)
            if !pending.isEmpty { followUpSection(pending) }
            ForEach(shown) { group in groupSection(group) }
            if groups.count > shown.count {
                Divider()
                Button("Show All \(groups.count) Groups") { withAnimation(.snappy(duration: 0.3)) { showAll = true } }
                    .buttonStyle(.borderless).font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 16).frame(minHeight: 40)
            }
        }
        .background(Color.panelStrong, in: .rect(cornerRadius: 16, style: .continuous))
        .clipShape(.rect(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.panelEdge))
        .animation(.snappy(duration: 0.3), value: groups)
        .animation(.snappy(duration: 0.3), value: model.reuseKeepers)
    }

    /// Logins given a new password from here that have since left their group: their site still has the old one.
    private var followUps: [VaultItem] {
        let reused = Set(groups.flatMap { $0.items.map(\.id) })
        return model.reuseFollowUps.compactMap { id in model.items.first { $0.id == id && !$0.isDeleted } }
            .filter { !reused.contains($0.id) }
    }

    private func followUpSection(_ items: [VaultItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 1) {
                Text("Finish on each site").font(.system(size: 12, weight: .semibold))
                Text("Saved here with a new password. Change it on the site too, then mark it done.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            ForEach(items) { item in
                HStack(spacing: 12) {
                    ItemIcon(item: item, size: 28)
                    itemText(item)
                    Spacer(minLength: 8)
                    if let host = item.host, !host.isEmpty { ChangeOnSiteButton(host: host) }
                    Button("Done") { withAnimation(.snappy(duration: 0.3)) { model.reuseFollowUps.removeAll { $0 == item.id } } }
                        .buttonStyle(.appSecondarySmall)
                        .help(Text("The site has the new password"))
                }
                .padding(.horizontal, 16).frame(minHeight: 48)
            }
        }
    }

    private func groupSection(_ group: WatchtowerReport.ReuseGroup) -> some View {
        let keeper = group.items.first { model.reuseKeepers.contains($0.id) }
        let selecting = selectingGroup == group.id
        return VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                Text("\(group.items.count) logins share a password").font(.system(size: 12, weight: .semibold))
                Text(keeper == nil ? "Pick the one to keep" : "Change the other \(group.items.count - 1)")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if selecting {
                    Button("Cancel") { selectingGroup = nil; selection = [] }
                        .buttonStyle(.borderless).font(.system(size: 12))
                    Button("Move \(selection.count) to Trash…") {
                        model.confirmBulk(.trash, Array(selection)) { selectingGroup = nil; selection = [] }
                    }
                    .buttonStyle(.appSecondarySmall)
                    .disabled(selection.isEmpty)
                } else {
                    Button("Select") { selectingGroup = group.id; selection = [] }
                        .buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(.secondary)
                        .help(Text("Pick logins in this group you no longer need, to move to Trash"))
                }
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
            ForEach(group.items) { item in
                row(item, group: group, keeper: keeper, selecting: selecting)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reuseGroup")
    }

    private func row(_ item: VaultItem, group: WatchtowerReport.ReuseGroup, keeper: VaultItem?, selecting: Bool) -> some View {
        let isKeeper = item.id == keeper?.id
        return HStack(spacing: 12) {
            if selecting {
                Toggle(isOn: Binding(get: { selection.contains(item.id) },
                                     set: { on in if on { selection.insert(item.id) } else { selection.remove(item.id) } })) {
                    Text(item.name)
                }
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(isKeeper)
                .help(isKeeper ? Text("You're keeping this one") : Text(verbatim: ""))
            }
            ItemIcon(item: item, size: 28)
            itemText(item)
            Spacer(minLength: 8)
            if !selecting {
                if isKeeper {
                    keepingBadge
                } else if keeper == nil {
                    Button("Keep This One") { model.keepReused(item, group: group.items) }
                        .buttonStyle(.appSecondarySmall)
                        .help(Text("This login keeps the password; the others get new ones"))
                } else {
                    if let host = item.host, !host.isEmpty { ChangeOnSiteButton(host: host) }
                    Button("New Password") { model.newPasswordForReused(item) }
                        .buttonStyle(.appSecondarySmall)
                        .help(Text("Make a new password with the generator and save it here"))
                }
                ActionMenu(entries: menu(item, group: group, isKeeper: isKeeper)) {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24).contentShape(.rect)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(Text("More"))
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 48)
        .background(Color.primary.opacity(highlighted == IssueCard.rowID(.reused, item.id) ? 0.07 : 0))
        .id(IssueCard.rowID(.reused, item.id))
    }

    /// Who this login is: its name, then its username and site. Never the password.
    private func itemText(_ item: VaultItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(verbatim: [item.username, item.host, item.isArchived ? String(localized: "Archived") : nil]
                .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    /// The kept login's quiet mark: a monochrome outlined badge, like Access history's outcomes.
    private var keepingBadge: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).accessibilityHidden(true)
            Text("Keeping").font(.system(size: 10, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .overlay { Capsule(style: .continuous).strokeBorder(.primary.opacity(0.12), lineWidth: 1) }
        .fixedSize()
    }

    private func menu(_ item: VaultItem, group: WatchtowerReport.ReuseGroup, isKeeper: Bool) -> [ActionMenuEntry] {
        var entries = [ActionMenuEntry(title: String(localized: "Show item"), symbol: "arrow.right.circle") { onOpen(item) }]
        if let username = item.username, !username.isEmpty {
            entries.append(ActionMenuEntry(title: String(localized: "Copy Username"), symbol: "person") { model.copyPlain(username) })
        }
        if !isKeeper {
            entries.append(ActionMenuEntry(title: String(localized: "Keep This One"), symbol: "checkmark", separatorBefore: true) {
                model.keepReused(item, group: group.items)
            })
            entries.append(ActionMenuEntry(title: String(localized: "New Password"), symbol: "dice") { model.newPasswordForReused(item) })
        }
        entries.append(ActionMenuEntry(title: String(localized: "Move to Trash…"), symbol: "trash", destructive: true, separatorBefore: true) {
            model.confirmTrash(item)
        })
        return entries
    }
}

/// The page where a site lets you change your password: its `/.well-known/change-password` (RFC 8615, as Safari
/// and Bitwarden use) when the site really has one, else the site itself. A site that answers 200 for any path
/// would fake support, so a path that can't exist is tried too. Only the site is asked, and results are kept for
/// the session.
enum ChangePasswordLink {
    @MainActor private static var known: [String: URL] = [:]

    @MainActor static func url(for host: String) async -> URL? {
        let host = host.lowercased()
        if let url = known[host] { return url }
        guard let site = URL(string: "https://\(host)"),
              let wellKnown = URL(string: "https://\(host)/.well-known/change-password"),
              let bogus = URL(string: "https://\(host)/.well-known/resource-that-should-not-exist-whose-status-code-should-not-be-200")
        else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        let session = URLSession(configuration: configuration)
        // HEAD first; sites that refuse it (405, 501) get a GET. Returns the status and where it ended up.
        func status(_ url: URL) async -> (code: Int, landed: URL?) {
            for method in ["HEAD", "GET"] {
                var request = URLRequest(url: url)
                request.httpMethod = method
                guard let (_, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse else { return (0, nil) }
                if method == "HEAD", [405, 501].contains(http.statusCode) { continue }
                return (http.statusCode, http.url)
            }
            return (0, nil)
        }
        async let realCheck = status(wellKnown)
        async let fakeCheck = status(bogus)
        let (real, fake) = await (realCheck, fakeCheck)
        // Supported when the address answers, and either a path that can't exist doesn't (no 2xx), or the two went
        // to different places (Netflix: /password, and a "not found" page that says 200). A site answering 200 for
        // everything without redirecting doesn't count.
        let redirected = real.landed.map { $0.path() != wellKnown.path() } ?? false
        let differs = real.landed?.path() != fake.landed?.path()
        let supported = (200..<400).contains(real.code) && (!(200..<300).contains(fake.code) || (redirected && differs))
        // The well-known address itself, not where it led here: without the browser's cookies it can end at a sign-in
        // page, while in the browser it goes straight to the right one.
        let url = supported ? wellKnown : site
        known[host] = url
        return url
    }
}

/// "Change on Site": opens the site's change-password page (or the site), finding it first.
struct ChangeOnSiteButton: View {
    let host: String
    @State private var finding = false

    var body: some View {
        Button {
            finding = true
            Task {
                if let url = await ChangePasswordLink.url(for: host) { NSWorkspace.shared.open(url) }
                finding = false
            }
        } label: {
            HStack(spacing: 5) {
                if finding { ProgressView().controlSize(.mini) }
                Text("Change on Site")
                Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold))
            }
        }
        .buttonStyle(.appSecondarySmall)
        .disabled(finding)
        .help(Text("Open \(host)'s page for changing the password"))
    }
}

/// Sites that offer one-time codes, from 2fa.directory: the whole list is downloaded (nothing about the vault is
/// sent) and kept for a week.
enum TwoFactorDirectory {
    static let source = URL(string: "https://api.2fa.directory/v3/totp.json")!

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "Triwarden")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "2fa-directory.json")
    }

    static func load() async -> [String: URL] {
        let cache = cacheURL
        let fresh = (try? cache.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { Date.now.timeIntervalSince($0) < 7 * 86_400 } ?? false
        if !fresh, let (data, response) = try? await URLSession.shared.data(from: source),
           (response as? HTTPURLResponse)?.statusCode == 200, !parse(data).isEmpty {
            try? data.write(to: cache, options: .atomic)
        }
        return (try? Data(contentsOf: cache)).map(parse) ?? [:]
    }

    /// `[[name, {domain, additional-domains, documentation, …}], …]` → domain: setup guide (or the site).
    static func parse(_ data: Data) -> [String: URL] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return [:] }
        var out: [String: URL] = [:]
        for entry in list {
            guard entry.count > 1, let info = entry[1] as? [String: Any], let domain = info["domain"] as? String else { continue }
            let guide = (info["documentation"] as? String).flatMap(URL.init(string:)) ?? URL(string: "https://" + domain)!
            for d in [domain] + (info["additional-domains"] as? [String] ?? []) { out[d.lowercased()] = guide }
        }
        return out
    }
}

extension VaultItem {
    /// The last day a card works (the end of its expiry month), if it has a month and year.
    var cardExpiry: Date? {
        guard kind == .card, let m = properties["expMonth"].flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }),
              var y = properties["expYear"].flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }), (1...12).contains(m) else { return nil }
        if y < 100 { y += 2000 }
        let calendar = Calendar.current
        guard let first = calendar.date(from: DateComponents(year: y, month: m, day: 1)),
              let next = calendar.date(byAdding: .month, value: 1, to: first) else { return nil }
        return next.addingTimeInterval(-1)
    }

    var isCardExpired: Bool { cardExpiry.map { $0 < .now } ?? false }

    /// "Expired 03/2025" or "Expires 11/2026".
    var cardExpiryText: String? {
        guard let expiry = cardExpiry else { return nil }
        let date = expiry.formatted(.dateTime.month(.twoDigits).year())
        return expiry < .now ? String(localized: "Expired \(date)") : String(localized: "Expires \(date)")
    }

    /// When the current password was set: the server's record, else when the one before it was replaced, else
    /// when the item was made.
    var passwordSince: Date? {
        guard password != nil else { return nil }
        return passwordRevised ?? passwordHistory.compactMap(\.date).max() ?? created
    }

    /// The worst thing Watchtower would say about this login's password, for a mark in the item list.
    func passwordIssue(breaches: [String: Int]?) -> WatchtowerReport.Issue? {
        guard kind == .login, !isDeleted, let pw = password, !pw.isEmpty else { return nil }
        if let n = breaches?[id], n > 0 { return .breached }
        if reuseCount > 0 { return .reused }
        if WatchtowerReport.isWeak(pw) { return .weak }
        if let uri, WatchtowerReport.isInsecure(uri) { return .insecure }
        return nil
    }
}
