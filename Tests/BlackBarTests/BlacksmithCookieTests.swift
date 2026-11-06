import Foundation
import Testing
import WebKit
@testable import BlackBar

@Suite("Blacksmith session cookies")
struct BlacksmithCookieTests {
    @Test("only Blacksmith hosts count as the saved session")
    func domains() {
        #expect(BlacksmithCookies.matches(domain: "app.blacksmith.sh"))
        #expect(BlacksmithCookies.matches(domain: ".blacksmith.sh"))
        #expect(BlacksmithCookies.matches(domain: "dashboardbackend.blacksmith.sh"))
        #expect(!BlacksmithCookies.matches(domain: "example.com"))
    }

    @Test("removal drops Blacksmith cookies and keeps the others")
    @MainActor
    func removal() async throws {
        let store = WKWebsiteDataStore.nonPersistent()
        let session = try #require(HTTPCookie(properties: [
            .domain: "app.blacksmith.sh",
            .path: "/",
            .name: "blacksmith_session",
            .value: "stored-session",
        ]))
        let other = try #require(HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: "keep-me",
            .value: "yes",
        ]))
        await store.httpCookieStore.setCookie(session)
        await store.httpCookieStore.setCookie(other)

        let before = await store.httpCookieStore.allCookies()
        await BlacksmithCookies.remove(from: store)
        let after = await store.httpCookieStore.allCookies()

        #expect(before.contains { $0.name == "blacksmith_session" })
        #expect(!after.contains { $0.name == "blacksmith_session" })
        #expect(after.contains { $0.name == "keep-me" })
    }

    @Test @MainActor
    func loginWindowStartsWithoutThePersistentStore() {
        let controller = BlacksmithLoginWindowController(owner: "openclaw") { _ in }
        #expect(controller.loginUsesPersistentStore == false)
        controller.close()
    }
}
