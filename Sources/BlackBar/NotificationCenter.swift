import AppKit
import Foundation
import UserNotifications

@MainActor
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifications()

    private let center = UNUserNotificationCenter.current()
    private var didSetDelegate = false
    private var authorizationRequested = false

    override init() {
        super.init()
    }

    func prepareIfNeeded() {
        if !didSetDelegate {
            center.delegate = self
            didSetDelegate = true
        }
    }

    func requestAuthorizationIfNeeded() async {
        prepareIfNeeded()
        guard !authorizationRequested else { return }
        authorizationRequested = true
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            authorizationRequested = false
        }
    }

    func post(id: String, title: String, body: String, url: URL?) async {
        prepareIfNeeded()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let url {
            content.userInfo = ["url": url.absoluteString]
        }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        do {
            try await center.add(request)
        } catch {
            // Posting failures are silent; the menu bar remains the source of truth.
        }
    }

    func post(_ event: NotificationEvent) async {
        await post(id: event.id, title: event.title, body: event.body, url: event.url)
    }

    func sendTestNotification() async {
        await requestAuthorizationIfNeeded()
        await post(
            id: "blackbar.test.\(UUID().uuidString)",
            title: "BlackBar",
            body: "Notifications are working.",
            url: nil
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }
}
