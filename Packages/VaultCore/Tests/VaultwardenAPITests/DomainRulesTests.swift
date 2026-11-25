import Foundation
import Testing
@testable import VaultwardenAPI

@Suite struct DomainRulesTests {
    private func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func decodesCamelCase() throws {
        let rules = DomainRules(json: try object(#"""
        {"equivalentDomains":[["Apple.com","icloud.com"]],
         "globalEquivalentDomains":[{"type":0,"domains":["youtube.com","google.com"],"excluded":false},
                                    {"type":1,"domains":["apple.com","icloud.com"],"excluded":true}],
         "object":"domains"}
        """#))
        #expect(rules.custom == [["apple.com", "icloud.com"]])
        #expect(rules.builtIn.map(\.type) == [0, 1])
        #expect(rules.builtIn[0].domains == ["youtube.com", "google.com"])
        #expect(rules.excludedBuiltInTypes == [1])
    }

    @Test func decodesPascalCase() throws {
        let rules = DomainRules(json: try object(#"""
        {"EquivalentDomains":[["a.example","b.example"]],
         "GlobalEquivalentDomains":[{"Type":7,"Domains":["x.example","y.example"],"Excluded":true}],"Object":"domains"}
        """#))
        #expect(rules.custom == [["a.example", "b.example"]])
        #expect(rules.builtIn == [.init(type: 7, domains: ["x.example", "y.example"], excluded: true)])
    }

    @Test func readsTheSyncPayloadsDomains() {
        let sync = #"{"Profile":{},"Domains":{"EquivalentDomains":[["a.example","b.example"]],"GlobalEquivalentDomains":[]}}"#
        #expect(DomainRules(syncData: Data(sync.utf8))?.custom == [["a.example", "b.example"]])
        #expect(DomainRules(syncData: Data(#"{"profile":{}}"#.utf8)) == nil)
    }

    @Test func missingOrNullListsAreEmpty() throws {
        let rules = DomainRules(json: try object(#"{"equivalentDomains":null,"globalEquivalentDomains":null}"#))
        #expect(rules.custom.isEmpty)
        #expect(rules.builtIn.isEmpty)
    }

    @Test func bodyCleansGroupsAndListsExclusions() throws {
        var rules = DomainRules(custom: [["https://www.Apple.com/login", "icloud.com", "ICLOUD.com"], ["lonely.example"],
                                         ["not a site", "ok.example"]],
                                builtIn: [.init(type: 4, domains: [], excluded: true), .init(type: 2, domains: [], excluded: false),
                                          .init(type: 3, domains: [], excluded: true)])
        #expect(rules.body["equivalentDomains"] as? [[String]] == [["apple.com", "icloud.com"]])
        #expect(rules.body["excludedGlobalEquivalentDomains"] as? [Int] == [3, 4])
        rules.builtIn[1].excluded = true
        #expect(rules.excludedBuiltInTypes == [2, 3, 4])
        // The body is valid JSON for the request.
        #expect(JSONSerialization.isValidJSONObject(rules.body))
    }

    @Test(arguments: [
        ("apple.com", "apple.com"),
        ("  iCloud.COM ", "icloud.com"),
        ("https://accounts.google.com/signin?x=1", "accounts.google.com"),
        ("example.com:8443", "example.com"),
        ("user@mail.example.com", "mail.example.com"),
        ("*.example.org", "example.org"),
        ("example.net.", "example.net"),
        ("bücher.de", "bücher.de"),
        ("192.168.1.10", "192.168.1.10"),
        ("https://WWW.Apple.com/", "apple.com"),
        ("www2.example.com", "www2.example.com"),
    ])
    func normalizesHosts(input: String, expected: String) {
        #expect(DomainRules.normalizedHost(input) == expected)
    }

    @Test(arguments: ["", "localhost", "two words.com", "-bad.com", "bad-.com", "a..b", "under_score.com", ".com"])
    func rejectsNonHosts(input: String) {
        #expect(DomainRules.normalizedHost(input) == nil)
    }
}
