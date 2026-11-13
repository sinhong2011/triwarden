import XCTest

final class SignUpEmailsTests: XCTestCase {
    /// The account's own email first, then the logins' most used ones; never non-emails; at most three.
    func testAccountFirstThenMostUsedLoginEmails() {
        let usernames = ["b@example.com", "a@example.com", " A@Example.com ", "alex", "c@example.com", "Me@Proton.me"]
        XCTAssertEqual(SignUpEmails.ranked(accounts: ["me@proton.me"], usernames: usernames),
                       ["me@proton.me", "a@example.com", "b@example.com"])
    }
}
