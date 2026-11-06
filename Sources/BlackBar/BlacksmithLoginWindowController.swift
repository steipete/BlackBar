import AppKit
import Foundation
import WebKit

@MainActor
final class BlacksmithLoginWindowController: NSWindowController, WKNavigationDelegate {
    typealias Completion = (Result<String, Error>) -> Void

    private let webView: WKWebView
    private let organization: String
    private let completion: Completion
    private var completed = false

    init(owner: String, completion: @escaping Completion) {
        self.organization = owner
        self.completion = completion
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Login to Blacksmith"
        window.center()
        window.contentView = webView
        super.init(window: window)
        webView.navigationDelegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        let redirect = "https://app.blacksmith.sh/\(organization)/runs/workflows"
        let encoded = redirect.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirect
        webView.load(URLRequest(url: URL(string: "https://dashboardbackend.blacksmith.sh/login/github?redirect=\(encoded)")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await finishIfAuthenticated() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        complete(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        complete(.failure(error))
    }

    private func finishIfAuthenticated() async {
        guard let host = webView.url?.host, host.contains("blacksmith.sh") else { return }
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let backendCookies = cookies.filter { BlacksmithCookies.matches(domain: $0.domain) }
        guard !backendCookies.isEmpty else { return }
        let header = backendCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        guard header.contains("blacksmith") || header.contains("session") || header.contains("XSRF") else { return }
        guard (try? await BlacksmithDashboardClient(cookieHeader: header).fetchUser()) != nil else { return }
        complete(.success(header))
    }

    var loginUsesPersistentStore: Bool {
        webView.configuration.websiteDataStore.isPersistent
    }

    private func complete(_ result: Result<String, Error>) {
        guard !completed else { return }
        completed = true
        completion(result)
        close()
    }
}
