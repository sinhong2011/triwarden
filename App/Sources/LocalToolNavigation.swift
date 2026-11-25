import Foundation

extension AppModel {
    /// Apply the same visibility rule to sidebar drawing, keyboard navigation, and requested destinations.
    func showsNavigation(_ destination: SidebarSelection) -> Bool {
        switch destination {
        case .section(.apiKeys), .toolLaunches: showsAPIKeyTools
        // Most vaults hold no bank account, licence or passport: Documents appears with the first (made from the + menu).
        case .section(.documents): items.contains { $0.kind.isDocument && !$0.isDeleted }
        default: true
        }
    }
}
