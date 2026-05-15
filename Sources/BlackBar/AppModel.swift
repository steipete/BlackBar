import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot = DashboardSnapshot.empty
    @Published var history: [Int] = []
    @Published var isRefreshing = false
    @Published var authState = AuthState.disconnected
    @Published var owner: String {
        didSet { defaults.set(owner, forKey: DefaultsKey.owner) }
    }
    @Published var repoFilter: String {
        didSet { defaults.set(repoFilter, forKey: DefaultsKey.repoFilter) }
    }
    @Published var pollInterval: TimeInterval {
        didSet {
            defaults.set(pollInterval, forKey: DefaultsKey.pollInterval)
            onPollIntervalChange?(pollInterval)
        }
    }
    @Published var notifyStatusChanges: Bool {
        didSet {
            defaults.set(notifyStatusChanges, forKey: DefaultsKey.notifyStatusChanges)
            if notifyStatusChanges { Task { await Notifications.shared.requestAuthorizationIfNeeded() } }
        }
    }
    @Published var notifyJobFinished: Bool {
        didSet {
            defaults.set(notifyJobFinished, forKey: DefaultsKey.notifyJobFinished)
            if notifyJobFinished { Task { await Notifications.shared.requestAuthorizationIfNeeded() } }
        }
    }
    @Published var notifyIncidents: Bool {
        didSet {
            defaults.set(notifyIncidents, forKey: DefaultsKey.notifyIncidents)
            if notifyIncidents { Task { await Notifications.shared.requestAuthorizationIfNeeded() } }
        }
    }

    var onSnapshotChange: (() -> Void)?
    var onPollIntervalChange: ((TimeInterval) -> Void)?

    private let defaults = UserDefaults.standard
    private let keychain = Keychain(service: "com.steipete.blackbar")
    private var loginWindow: BlacksmithLoginWindowController?
    private var cachedCookieHeader: String?

    init() {
        owner = defaults.string(forKey: DefaultsKey.owner) ?? "openclaw"
        repoFilter = defaults.string(forKey: DefaultsKey.repoFilter) ?? ""
        let interval = defaults.double(forKey: DefaultsKey.pollInterval)
        pollInterval = interval > 0 ? interval : 60
        history = defaults.array(forKey: DefaultsKey.history) as? [Int] ?? []
        notifyStatusChanges = defaults.bool(forKey: DefaultsKey.notifyStatusChanges)
        notifyJobFinished = defaults.bool(forKey: DefaultsKey.notifyJobFinished)
        notifyIncidents = defaults.bool(forKey: DefaultsKey.notifyIncidents)
        Task { await loadAuthState() }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let cookieHeader = try currentCookieHeader()
            let client = BlacksmithDashboardClient(cookieHeader: cookieHeader)
            async let blacksmithStatus = BlacksmithStatusClient.fetch()
            async let usage = client.fetchUsage(owner: owner, repoFilter: repoFilter)
            let newUsage = try await usage
            let newStatus: BlacksmithStatus
            let statusError: String?
            do {
                newStatus = try await blacksmithStatus
                statusError = nil
            } catch {
                newStatus = snapshot.status
                statusError = "Status unavailable: \(Self.errorMessage(error))"
            }

            let newSnapshot = DashboardSnapshot(
                status: newStatus,
                usage: newUsage,
                refreshedAt: Date(),
                error: statusError
            )
            apply(newSnapshot)
            await refreshViewer(client: client)
        } catch {
            let failed = DashboardSnapshot(
                status: snapshot.status,
                usage: snapshot.usage,
                refreshedAt: Date(),
                error: Self.errorMessage(error)
            )
            apply(failed)
        }
    }

    func loginWithGitHub() {
        let controller = BlacksmithLoginWindowController(owner: owner) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.loginWindow = nil
                switch result {
                case .success(let cookieHeader):
                    do {
                        try self.keychain.set(cookieHeader, account: "blacksmith-cookie")
                        self.cachedCookieHeader = cookieHeader
                        self.authState = .connected(login: nil)
                        await self.refresh()
                    } catch {
                        self.snapshot = self.snapshot.with(error: Self.errorMessage(error))
                    }
                case .failure(let error):
                    self.snapshot = self.snapshot.with(error: Self.errorMessage(error))
                }
            }
        }
        loginWindow = controller
        controller.showWindow(nil)
    }

    func signOut() {
        cachedCookieHeader = nil
        try? keychain.delete(account: "blacksmith-cookie")
        authState = .disconnected
        apply(.empty.with(error: "Blacksmith disconnected"))
    }

    func openBlacksmith() {
        NSWorkspace.shared.open(URL(string: "https://app.blacksmith.sh/\(owner)/runs/workflows")!)
    }

    func openBlacksmithStatus() {
        NSWorkspace.shared.open(URL(string: "https://status.blacksmith.sh/")!)
    }

    func openGitHubActions() {
        let trimmed = repoFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = trimmed.isEmpty ? "https://github.com/orgs/\(owner)/actions" : "https://github.com/\(owner)/\(trimmed)/actions"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func currentCookieHeader() throws -> String {
        if let cachedCookieHeader, !cachedCookieHeader.isEmpty {
            return cachedCookieHeader
        }
        if let cookieHeader = try keychain.get(account: "blacksmith-cookie"), !cookieHeader.isEmpty {
            cachedCookieHeader = cookieHeader
            return cookieHeader
        }
        throw AppError.missingCookie
    }

    private func refreshViewer(client: BlacksmithDashboardClient) async {
        do {
            let user = try await client.fetchUser()
            authState = .connected(login: user.name ?? user.email)
        } catch {
            authState = .connected(login: nil)
        }
    }

    private func loadAuthState() async {
        do {
            _ = try currentCookieHeader()
            authState = .connected(login: nil)
        } catch {
            authState = .disconnected
        }
    }

    private func apply(_ newSnapshot: DashboardSnapshot) {
        let previousSnapshot = snapshot
        snapshot = newSnapshot
        if newSnapshot.usage.historyVCPU.isEmpty {
            history.append(max(0, newSnapshot.usage.activeVCPU))
        } else {
            history = Array(newSnapshot.usage.historyVCPU.suffix(48))
        }
        if history.count > 48 {
            history.removeFirst(history.count - 48)
        }
        defaults.set(history, forKey: DefaultsKey.history)
        emitNotifications(previous: previousSnapshot, current: newSnapshot)
        onSnapshotChange?()
    }

    private func emitNotifications(previous: DashboardSnapshot, current: DashboardSnapshot) {
        let preferences = NotificationPreferences(
            statusChanges: notifyStatusChanges,
            jobFinished: notifyJobFinished,
            incidents: notifyIncidents
        )
        for event in NotificationPlanner.events(previous: previous, current: current, preferences: preferences) {
            Task { await Notifications.shared.post(event) }
        }
    }

    private static func errorMessage(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            switch decodingError {
            case .keyNotFound(let key, _):
                return "Missing API field: \(key.stringValue)"
            case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
                return context.debugDescription
            @unknown default:
                return decodingError.localizedDescription
            }
        }
        return error.localizedDescription
    }

}

enum AuthState: Equatable {
    case disconnected
    case connected(login: String?)

    var label: String {
        switch self {
        case .disconnected:
            "Blacksmith disconnected"
        case .connected(let login):
            login.map { "Blacksmith \($0)" } ?? "Blacksmith connected"
        }
    }
}

enum DefaultsKey {
    static let owner = "owner"
    static let repoFilter = "repoFilter"
    static let pollInterval = "pollInterval"
    static let history = "history"
    static let notifyStatusChanges = "notifyStatusChanges"
    static let notifyJobFinished = "notifyJobFinished"
    static let notifyIncidents = "notifyIncidents"
}

enum AppError: LocalizedError {
    case missingCookie

    var errorDescription: String? {
        switch self {
        case .missingCookie:
            "Login to Blacksmith with GitHub."
        }
    }
}
