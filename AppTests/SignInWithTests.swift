import XCTest

final class SignInWithTests: XCTestCase {
    func testFieldValueParsing() {
        XCTAssertEqual(SignInProvider(fieldValue: "Google"), .google)
        XCTAssertEqual(SignInProvider(fieldValue: " sign in with Apple "), .apple)
        XCTAssertEqual(SignInProvider(fieldValue: "github"), .github)
        XCTAssertEqual(SignInProvider(fieldValue: "Twitter"), .x)
        XCTAssertNil(SignInProvider(fieldValue: "My Company SSO"))
        XCTAssertNil(SignInProvider(fieldValue: ""))
    }

    /// The field the app writes reads back as the same provider.
    func testDisplayNameRoundTrips() {
        for provider in SignInProvider.allCases {
            XCTAssertEqual(SignInProvider(fieldValue: provider.displayName), provider)
        }
    }

    func testEmailCheck() {
        XCTAssertTrue(SignInProvider.isEmail("me@gmail.com"))
        XCTAssertFalse(SignInProvider.isEmail("me @gmail.com"))
        XCTAssertFalse(SignInProvider.isEmail("not-an-email"))
        XCTAssertFalse(SignInProvider.isEmail(String(repeating: "a", count: 250) + "@x.io"))
    }
}
