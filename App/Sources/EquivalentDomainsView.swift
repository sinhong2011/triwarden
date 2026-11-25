import SwiftUI
import VaultwardenAPI

/// An account's sites that share sign-ins (the server's equivalent domains), as a section of its page in Settings:
/// what's set now, and the editor.
struct EquivalentDomainsSection: View {
    let session: AccountSession
    @State private var editing = false
    /// The account's rules as the server has them. Sync leaves turned-off built-in groups out altogether, so only
    /// this says how many are off.
    @State private var rules: DomainRules?

    var body: some View {
        Section {
            LabeledContent {
                Button("Edit…") { editing = true }
            } label: {
                Text(summary)
                Text("For example apple.com and icloud.com: a login saved for one is offered on the other.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Sites that share sign-ins")
        } footer: {
            Text("AutoFill, the command palette and the browser extension use these groups. They're saved with your account, so your other Bitwarden apps use them too.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $editing) { EquivalentDomainsSheet(session: session) }
        // Again after each sync, which includes the one that follows a save.
        .task(id: session.lastSynced) {
            if let loaded = try? await session.domainRules() { rules = loaded }
        }
    }

    private var summary: String {
        // Offline: your own groups still come down with sync; how many built-in ones are off doesn't.
        guard let rules = rules ?? session.syncedDomainRules else { return String(localized: "Bitwarden's built-in groups") }
        let own = DomainRules.cleaned(rules.custom).count, off = rules.excludedBuiltInTypes.count
        switch (own, off) {
        case (0, 0): return String(localized: "Bitwarden's built-in groups")
        case (_, 0): return String(localized: "^[\(own) group](inflect: true) of your own, plus the built-in ones")
        case (0, _): return String(localized: "Built-in groups, \(off) turned off")
        default: return String(localized: "^[\(own) group](inflect: true) of your own · ^[\(off) built-in group](inflect: true) off")
        }
    }
}

/// Edits one account's groups: your own (add or remove sites, add or remove groups), and the built-in ones (turn a
/// group off). Nothing changes until Save; saving syncs, so matching everywhere follows at once.
struct EquivalentDomainsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let session: AccountSession?
    /// Snapshots: shown instead of loading from the server.
    var preview: DomainRules?
    @State var tab: Tab = .own

    enum Tab: Hashable { case own, builtIn }

    /// A group being edited: its sites, and what's typed into its Add field.
    struct EditedGroup: Identifiable, Equatable {
        let id = UUID()
        var sites: [String]
        var draft = ""
        var problem: String?
    }

    @State private var original: DomainRules?
    @State private var groups: [EditedGroup] = []
    @State private var builtIn: [DomainRules.BuiltInGroup] = []
    @State private var search = ""
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var busy = false
    @FocusState private var focusedGroup: UUID?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                FormHeader(symbol: "link", title: "Sites that share sign-ins",
                           subtitle: "A login saved for one site in a group is offered on the others.")
                AppSegmented(options: [(Tab.own, "Your groups"), (Tab.builtIn, "Built-in groups")], selection: $tab)
                    .frame(maxWidth: 340)
            }
            .padding([.horizontal, .top], 20).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().opacity(0.5)
            content.frame(maxHeight: .infinity)

            FormFooter(action: "Save", busy: busy, disabled: original == nil || !changed || incomplete,
                       cancel: { dismiss() }, submit: save) {
                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundStyle(.red)
                        .lineLimit(2)
                } else if let short = groups.firstIndex(where: { $0.sites.count == 1 }) {
                    // Named, since it may be off screen or on the other tab.
                    Text("Group \(short + 1) needs at least two sites.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 560, height: 600)
        .background(Color.windowBase)
        .task { await load() }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if let loadError {
            VStack(spacing: 10) {
                Label(loadError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Button("Try Again") { Task { await load() } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if original == nil {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .own: ownGroups
                    case .builtIn: builtInGroups
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .thinScroller()
        }
    }

    @ViewBuilder private var ownGroups: some View {
        if groups.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No groups of your own yet").font(.system(size: 13, weight: .semibold))
                Text("Make one when a site uses a sign-in from another address, for example apple.com and icloud.com, or your company's sites.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)
        }
        ForEach($groups) { $group in
            groupCard($group, number: (groups.firstIndex { $0.id == group.id } ?? 0) + 1)
        }
        Button {
            let group = EditedGroup(sites: [])
            groups.append(group)
            focusedGroup = group.id
        } label: {
            Label("New Group", systemImage: "plus")
        }
        .buttonStyle(.appSecondarySmall)
    }

    private func groupCard(_ group: Binding<EditedGroup>, number: Int) -> some View {
        FormCard {
            HStack {
                Text("Group \(number)").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Remove Group", role: .destructive) { groups.removeAll { $0.id == group.wrappedValue.id } }
                    .buttonStyle(.borderless).font(.system(size: 12))
            }
            if !group.wrappedValue.sites.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(group.wrappedValue.sites, id: \.self) { site in
                        SiteChip(site: site) { group.wrappedValue.sites.removeAll { $0 == site } }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField("Add a site, like icloud.com", text: group.draft)
                        .textFieldStyle(SoftFieldStyle())
                        .focused($focusedGroup, equals: group.wrappedValue.id)
                        .onSubmit { add(to: group) }
                        .onChange(of: group.wrappedValue.draft) { group.wrappedValue.problem = nil }
                    Button("Add") { add(to: group) }
                        .buttonStyle(.appSecondarySmall)
                        .disabled(group.wrappedValue.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let problem = group.wrappedValue.problem {
                    Text(problem).font(.system(size: 11)).foregroundStyle(.red)
                } else if group.wrappedValue.sites.count == 1 {
                    Text("Add one more site to share this sign-in with.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var builtInGroups: some View {
        Text("Bitwarden keeps these groups up to date for everyone. Turn one off if its sites shouldn't share sign-ins for you.")
            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
        HStack(spacing: 8) {
            TextField("Find a site", text: $search).textFieldStyle(SoftFieldStyle())
            if builtIn.contains(where: \.excluded) {
                Button("Turn All On") { for i in builtIn.indices { builtIn[i].excluded = false } }
                    .buttonStyle(.appSecondarySmall)
            }
        }
        let shown = filteredBuiltIn
        if shown.isEmpty {
            Text(builtIn.isEmpty ? "This server has no built-in groups." : "No built-in group has that site.")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 4)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { offset, group in
                    if offset > 0 { Divider().padding(.leading, 14) }
                    builtInRow(group)
                }
            }
            .background(Color.panelStrong, in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.panelEdge))
        }
    }

    private func builtInRow(_ group: DomainRules.BuiltInGroup) -> some View {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        // The site you searched for first, so you can see why the group is here.
        let ordered = query.isEmpty ? group.domains
            : group.domains.filter { $0.contains(query) } + group.domains.filter { !$0.contains(query) }
        let head = ordered.prefix(3).joined(separator: ", "), more = max(0, ordered.count - 3)
        return Toggle(isOn: Binding(get: { !group.excluded }, set: { on in
            if let i = builtIn.firstIndex(where: { $0.type == group.type }) { builtIn[i].excluded = !on }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: head).font(.system(size: 13)).lineLimit(1).truncationMode(.tail)
                if more > 0 {
                    Text("and ^[\(more) more site](inflect: true)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            // Sites on the left, the switch at the row's right edge (outside a Form the switch hugs its label).
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(group.domains.joined(separator: ", "))
        }
        .toggleStyle(.brandSwitch)
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private var filteredBuiltIn: [DomainRules.BuiltInGroup] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return builtIn }
        return builtIn.filter { $0.domains.contains { $0.contains(query) } }
    }

    // MARK: Editing

    /// Adds what's typed: one site, or several separated by commas or spaces. A whole address is fine; only its
    /// site is kept.
    private func add(to group: Binding<EditedGroup>) {
        let entries = group.wrappedValue.draft.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        guard !entries.isEmpty else { return }
        var hosts: [String] = []
        for entry in entries {
            guard let host = DomainRules.normalizedHost(entry) else {
                group.wrappedValue.problem = String(localized: "“\(entry)” isn't a site address. Try something like icloud.com.")
                return
            }
            if !group.wrappedValue.sites.contains(host), !hosts.contains(host) { hosts.append(host) }
        }
        if hosts.isEmpty {
            group.wrappedValue.problem = String(localized: "That site is already in this group.")
            return
        }
        group.wrappedValue.sites += hosts
        group.wrappedValue.draft = ""
    }

    /// Groups as they'd be saved.
    private var edited: DomainRules {
        DomainRules(custom: DomainRules.cleaned(groups.map(\.sites)), builtIn: builtIn)
    }

    private var changed: Bool {
        guard let original else { return false }
        return DomainRules.cleaned(original.custom) != edited.custom || original.excludedBuiltInTypes != edited.excludedBuiltInTypes
    }

    /// A group with just one site: saving would quietly drop it.
    private var incomplete: Bool { groups.contains { $0.sites.count == 1 } }

    private func load() async {
        loadError = nil
        let rules: DomainRules
        if let preview {
            rules = preview
        } else if let session {
            do { rules = try await session.domainRules() } catch {
                loadError = String(localized: "Couldn't load this account's groups: \(problem(error))")
                return
            }
        } else { return }
        original = rules
        groups = rules.custom.map { EditedGroup(sites: $0) }
        builtIn = rules.builtIn
    }

    private func save() {
        guard let session, changed, !incomplete else { return }
        busy = true
        saveError = nil
        let rules = edited
        Task {
            defer { busy = false }
            do {
                let synced = try await session.saveDomainRules(rules)
                model.flash(synced ? String(localized: "Saved. Matching uses the new groups now.")
                                   : String(localized: "Saved. The new groups apply after the next sync."))
                dismiss()
            } catch {
                saveError = String(localized: "Couldn't save: \(problem(error))")
            }
        }
    }

    private func problem(_ error: Error) -> String {
        switch error {
        case APIError.http(_, let message?): message
        case APIError.http(let status, nil): String(localized: "Server error (\(status)).")
        case AccountSession.WriteError.offline: String(localized: "This account is offline.")
        default: String(localized: "Couldn't reach the server.")
        }
    }
}

/// One site in a group, with a button to take it out.
private struct SiteChip: View {
    let site: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: site).font(.system(size: 12, weight: .medium))
            Button(action: remove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                    .frame(width: 14, height: 14).contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(site)"))
        }
        .padding(.leading, 9).padding(.trailing, 5).padding(.vertical, 4)
        .background(.primary.opacity(0.06), in: .capsule)
    }
}
