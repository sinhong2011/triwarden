import Foundation

extension AppModel {
    /// Apply the same visibility rule to sidebar drawing, keyboard navigation, and requested destinations.
    func showsNavigation(_ destination: SidebarSelection) -> Bool {
        switch destination {
        case .section(.apiKeys), .toolLaunches: showsAPIKeyTools
        // Most vaults hold none of these: their sections appear with the first one (made from the + menu).
        case .section(let section) where section.documentKind != nil:
            items.contains { $0.kind == section.documentKind && !$0.isDeleted }
        default: true
        }
    }
}
