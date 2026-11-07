import XCTest

final class WebsiteSiteOnlyTests: XCTestCase {
    func testDropsPathQueryAndFragment() {
        XCTAssertEqual(WebsiteSiteOnly.trimmed("https://example.com/login?redirect=x&client_id=1#top"), "https://example.com")
        XCTAssertEqual(WebsiteSiteOnly.trimmed("  https://accounts.example.com/o/oauth2/callback?code=abc \n"), "https://accounts.example.com")
    }

    func testKeepsSchemeHostAndPort() {
        XCTAssertEqual(WebsiteSiteOnly.trimmed("http://www.example.com/a"), "http://www.example.com")
        XCTAssertEqual(WebsiteSiteOnly.trimmed("https://example.com:8443/admin"), "https://example.com:8443")
        XCTAssertEqual(WebsiteSiteOnly.trimmed("http://[::1]:8080/x"), "http://[::1]:8080")
    }

    func testWithoutSchemeStaysWithoutScheme() {
        XCTAssertEqual(WebsiteSiteOnly.trimmed("example.com/sign-in"), "example.com")
    }

    func testDropsSignInDetails() {
        XCTAssertEqual(WebsiteSiteOnly.trimmed("https://user:pw@example.com"), "https://example.com")
    }

    func testNothingToTrim() {
        XCTAssertNil(WebsiteSiteOnly.trimmed("https://example.com"))
        XCTAssertNil(WebsiteSiteOnly.trimmed("https://example.com/"))
        XCTAssertNil(WebsiteSiteOnly.trimmed("example.com"))
        XCTAssertNil(WebsiteSiteOnly.trimmed(""))
        XCTAssertEqual(WebsiteSiteOnly.apply("https://example.com"), "https://example.com")
    }

    func testLeavesAppLinksAlone() {
        XCTAssertNil(WebsiteSiteOnly.trimmed("androidapp://com.example.app/path"))
        XCTAssertNil(WebsiteSiteOnly.trimmed("iosapp://com.example.app"))
    }
}
