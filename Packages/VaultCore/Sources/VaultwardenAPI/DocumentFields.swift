import Foundation

/// The properties of Bitwarden's document item types — bank account (6), driver's licence (7) and passport (8) — in the
/// order the official clients declare them. Every value is an EncString on the wire; dates are free text, as Bitwarden
/// keeps them. Properties a newer server adds are not listed here and pass through edits, exports and moves untouched.
public struct DocumentField: Sendable, Hashable {
    /// The property's name in the cipher's JSON object (e.g. "accountNumber").
    public let key: String
    /// An English label, for exports that carry no translation (KeePass).
    public let label: String
    /// Masked until revealed, and protected in KeePass.
    public let secret: Bool

    init(_ key: String, _ label: String, secret: Bool = false) {
        self.key = key; self.label = label; self.secret = secret
    }

    public static func fields(for kind: CipherEditor.Kind) -> [DocumentField] {
        switch kind {
        case .bankAccount: bankAccount
        case .driversLicense: driversLicense
        case .passport: passport
        default: []
        }
    }

    public static let bankAccount: [DocumentField] = [
        .init("bankName", "Bank name"), .init("nameOnAccount", "Name on account"), .init("accountType", "Account type"),
        .init("accountNumber", "Account number", secret: true), .init("routingNumber", "Routing number"),
        .init("branchNumber", "Branch number"), .init("pin", "PIN", secret: true), .init("swiftCode", "SWIFT / BIC"),
        .init("iban", "IBAN", secret: true), .init("bankContactPhone", "Bank phone"),
    ]

    public static let driversLicense: [DocumentField] = [
        .init("firstName", "First name"), .init("middleName", "Middle name"), .init("lastName", "Last name"),
        .init("dateOfBirth", "Date of birth"), .init("licenseNumber", "License number", secret: true),
        .init("issuingCountry", "Issuing country"), .init("issuingState", "Issuing state"), .init("issueDate", "Issue date"),
        .init("issuingAuthority", "Issuing authority"), .init("expirationDate", "Expiration date"),
        .init("licenseClass", "License class"),
    ]

    public static let passport: [DocumentField] = [
        .init("surname", "Surname"), .init("givenName", "Given name"), .init("dateOfBirth", "Date of birth"),
        .init("sex", "Sex"), .init("birthPlace", "Place of birth"), .init("nationality", "Nationality"),
        .init("passportNumber", "Passport number", secret: true), .init("passportType", "Passport type"),
        .init("issuingCountry", "Issuing country"), .init("issuingAuthority", "Issuing authority"),
        .init("issueDate", "Issue date"), .init("expirationDate", "Expiration date"),
        .init("nationalIdentificationNumber", "National ID number", secret: true),
    ]

    /// The line under the item's name in a list, as the official clients build it: the bank's name; the holder's name
    /// and issuing state; the holder's name and issuing country.
    public static func subtitle(for kind: CipherEditor.Kind, _ value: (String) -> String?) -> String? {
        func join(_ parts: [String?], _ separator: String) -> String? {
            parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: separator).nilIfBlank
        }
        switch kind {
        case .bankAccount: return value("bankName")?.nilIfBlank ?? value("nameOnAccount")?.nilIfBlank
        case .driversLicense:
            return join([join([value("firstName"), value("lastName")], " "), value("issuingState") ?? value("issuingCountry")], ", ")
        case .passport:
            return join([join([value("givenName"), value("surname")], " "), value("issuingCountry")], ", ")
        default: return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
