import SwiftUI
import VaultwardenAPI

/// An organization's event log: who did what, newest first.
struct EventLogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let organizationId: String
    @State private var days = 7
    @State private var events: [OrgEvent] = []
    @State private var names: [String: String] = [:]
    @State private var loading = true
    @State private var error: String?

    private var organization: Grouping? { model.organizations.first { $0.id == organizationId } }
    private var session: AccountSession? { model.sessions.first { $0.organizations.contains { $0.id == organizationId } } }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    FormHeader(symbol: "list.bullet.rectangle", title: "Event log", subtitle: "\(organization?.name ?? "")")
                    Spacer()
                    AppSegmented(options: [(1, LocalizedStringKey("Day")), (7, "Week"), (30, "Month")], selection: $days)
                        .accessibilityLabel(Text("Event log"))
                        .frame(width: 220)
                }
                FormCard {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    } else if let error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    } else if events.isEmpty {
                        Text("No events. The server keeps them only when its administrator turns event logging on (ORG_EVENTS_ENABLED).")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(events) { event in row(event) }
                            }
                        }
                        .frame(height: 360)
                    }
                }
            }
            .padding(20)
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.appPrimary).keyboardShortcut(.defaultAction) }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(alignment: .top) { Divider().opacity(0.5) }
        }
        .frame(width: 620)
        .background(Color.windowBase)
        .task(id: days) { await load() }
    }

    private func load() async {
        guard let session else { return }
        loading = true
        defer { loading = false }
        do {
            (events, names) = try await session.organizationEvents(organizationId, days: days)
            error = nil
        } catch {
            self.error = String(localized: "Only owners and admins can see the event log.")
        }
    }

    private func row(_ event: OrgEvent) -> some View {
        let (text, symbol) = Self.describe(event, item: event.cipherId.flatMap { id in model.items.first { $0.id == id }?.name },
                                           member: event.memberId.flatMap { names[$0] })
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: text).font(.system(size: 13))
                HStack(spacing: 6) {
                    Text(verbatim: event.actingUserId.flatMap { names[$0] } ?? String(localized: "Someone"))
                    if let date = VaultDecoder.date(event.date) {
                        Text(verbatim: "·")
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let ip = event.ipAddress { Text(verbatim: "· \(ip)") }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    /// Bitwarden's event types, in words.
    static func describe(_ e: OrgEvent, item: String?, member: String?) -> (String, String) {
        let thing = item.map { "“\($0)”" } ?? String(localized: "an item")
        let who = member ?? String(localized: "a member")
        switch e.type {
        case 1000: return (String(localized: "Signed in"), "person.badge.key")
        case 1001: return (String(localized: "Changed their master password"), "key")
        case 1002: return (String(localized: "Changed two-step login"), "lock.shield")
        case 1003: return (String(localized: "Turned off two-step login"), "lock.open")
        case 1005, 1006: return (String(localized: "Failed to sign in"), "exclamationmark.triangle")
        case 1007: return (String(localized: "Exported the vault"), "square.and.arrow.up")
        case 1100: return (String(localized: "Created \(thing)"), "plus.circle")
        case 1101: return (String(localized: "Edited \(thing)"), "pencil")
        case 1102: return (String(localized: "Deleted \(thing) permanently"), "trash.slash")
        case 1103: return (String(localized: "Attached a file to \(thing)"), "paperclip")
        case 1104: return (String(localized: "Removed a file from \(thing)"), "paperclip")
        case 1105: return (String(localized: "Moved \(thing) into a shared vault"), "building.2")
        case 1106: return (String(localized: "Changed the shared folders of \(thing)"), "rectangle.stack")
        case 1107: return (String(localized: "Viewed \(thing)"), "eye")
        case 1108...1110, 1117: return (String(localized: "Revealed a secret in \(thing)"), "eye")
        case 1111...1113: return (String(localized: "Copied a secret from \(thing)"), "doc.on.doc")
        case 1114: return (String(localized: "Filled \(thing)"), "text.cursor")
        case 1115: return (String(localized: "Moved \(thing) to Trash"), "trash")
        case 1116: return (String(localized: "Restored \(thing)"), "arrow.uturn.backward")
        case 1300: return (String(localized: "Created a shared folder"), "rectangle.stack.badge.plus")
        case 1301: return (String(localized: "Edited a shared folder"), "rectangle.stack")
        case 1302: return (String(localized: "Deleted a shared folder"), "rectangle.stack.badge.minus")
        case 1400...1499: return (String(localized: "Changed a group"), "person.3")
        case 1500: return (String(localized: "Invited \(who)"), "person.badge.plus")
        case 1501: return (String(localized: "Confirmed \(who)"), "person.badge.shield.checkmark")
        case 1502, 1504: return (String(localized: "Changed \(who)'s access"), "person.crop.circle.badge.questionmark")
        case 1503: return (String(localized: "Removed \(who)"), "person.badge.minus")
        case 1511: return (String(localized: "Revoked \(who)"), "person.slash")
        case 1512: return (String(localized: "Restored \(who)"), "person")
        case 1600...1699: return (String(localized: "Changed the shared vault's settings"), "building.2")
        case 1700...1799: return (String(localized: "Changed a policy"), "checklist")
        default: return (String(localized: "Event \(e.type)"), "circle")
        }
    }
}
