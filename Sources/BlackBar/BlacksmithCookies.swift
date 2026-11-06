import Foundation
import WebKit

enum BlacksmithCookies {
    static func matches(domain: String) -> Bool {
        domain.contains("blacksmith.sh") || domain.contains("dashboardbackend.blacksmith.sh")
    }

    @MainActor
    static func remove(from store: WKWebsiteDataStore) async {
        let cookies = await store.httpCookieStore.allCookies()
        for cookie in cookies where matches(domain: cookie.domain) {
            await store.httpCookieStore.deleteCookie(cookie)
        }
    }
}

extension WKHTTPCookieStore {
    func deleteCookie(_ cookie: HTTPCookie) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            delete(cookie) {
                continuation.resume()
            }
        }
    }
}
