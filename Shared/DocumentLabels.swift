import Foundation
import VaultwardenAPI

// Shared by the app and the AutoFill extension: how bank accounts, driver's licences and passports read on screen.

extension DocumentField {
    /// The property's label in the user's language.
    var localizedLabel: String {
        switch key {
        case "bankName": String(localized: "Bank name")
        case "nameOnAccount": String(localized: "Name on account")
        case "accountType": String(localized: "Account type")
        case "accountNumber": String(localized: "Account number")
        case "routingNumber": String(localized: "Routing number")
        case "branchNumber": String(localized: "Branch number")
        case "pin": String(localized: "PIN")
        case "swiftCode": String(localized: "SWIFT / BIC")
        case "iban": String(localized: "IBAN")
        case "bankContactPhone": String(localized: "Bank phone")
        case "firstName": String(localized: "First name")
        case "middleName": String(localized: "Middle name")
        case "lastName": String(localized: "Last name")
        case "dateOfBirth": String(localized: "Date of birth")
        case "licenseNumber": String(localized: "Licence number")
        case "issuingCountry": String(localized: "Issuing country")
        case "issuingState": String(localized: "Issuing state / province")
        case "issueDate": String(localized: "Issue date")
        case "issuingAuthority": String(localized: "Issuing authority")
        case "expirationDate": String(localized: "Expiry date")
        case "licenseClass": String(localized: "Licence class")
        case "surname": String(localized: "Surname")
        case "givenName": String(localized: "Given names")
        case "sex": String(localized: "Sex")
        case "birthPlace": String(localized: "Place of birth")
        case "nationality": String(localized: "Nationality")
        case "passportNumber": String(localized: "Passport number")
        case "passportType": String(localized: "Passport type")
        case "nationalIdentificationNumber": String(localized: "National ID number")
        default: label
        }
    }

    /// A property this version doesn't list, named in plain words from its API name: "visaPages" → "Visa pages".
    static func readableName(_ key: String) -> String {
        var words = ""
        for character in key {
            if character.isUppercase, !words.isEmpty { words.append(" ") }
            words.append(contentsOf: words.isEmpty ? character.uppercased() : character.lowercased())
        }
        return words.isEmpty ? key : words
    }

    /// Account and document numbers read best in a fixed-width face.
    var monospaced: Bool {
        ["accountNumber", "routingNumber", "branchNumber", "pin", "swiftCode", "iban", "licenseNumber", "passportNumber",
         "nationalIdentificationNumber"].contains(key)
    }
}

extension VaultItem.Kind {
    /// Bitwarden's kind for this item, when it is one of the document types.
    var documentKind: CipherEditor.Kind? {
        switch self {
        case .bankAccount: .bankAccount
        case .driversLicense: .driversLicense
        case .passport: .passport
        default: nil
        }
    }

    var isDocument: Bool { documentKind != nil }
}

extension VaultItem {
    /// Sets a document's properties (by API name), with the list subtitle and the detail rows they make. Properties a
    /// newer Bitwarden added come last under their API name, hidden like a secret until revealed.
    mutating func setDocumentProperties(_ values: [String: String]) {
        guard let documentKind = kind.documentKind else { return }
        properties = values.filter { !$0.value.isEmpty }
        let known = DocumentField.fields(for: documentKind)
        username = DocumentField.subtitle(for: documentKind) { properties[$0] }
        fields = known.compactMap { field in
            properties[field.key].map { ItemField(label: field.localizedLabel, value: $0, secret: field.secret, monospaced: field.monospaced) }
        }
        fields += properties.keys.filter { key in !known.contains { $0.key == key } }.sorted().map {
            ItemField(label: DocumentField.readableName($0), value: properties[$0] ?? "", secret: true)
        }
    }
}
