import Foundation

struct NotificationPreferences: Equatable {
    var statusChanges: Bool
    var jobFinished: Bool
    var incidents: Bool
}

struct NotificationEvent: Equatable {
    var id: String
    var title: String
    var body: String
    var url: URL?
}

enum NotificationPlanner {
    static func events(
        previous: DashboardSnapshot,
        current: DashboardSnapshot,
        preferences: NotificationPreferences
    ) -> [NotificationEvent] {
        var events: [NotificationEvent] = []
        let previousPage = previous.status.pageStatus.uppercased()
        let currentPage = current.status.pageStatus.uppercased()
        let hasStatusTransitionContext = previousPage != "UNKNOWN" && currentPage != "UNKNOWN" && previous.refreshedAt != nil && current.refreshedAt != nil

        if preferences.statusChanges && hasStatusTransitionContext && previousPage != currentPage {
            let title: String
            let body: String
            if currentPage == "UP" {
                title = "Blacksmith operational"
                body = "Status is back to UP after \(previous.status.label)."
            } else {
                title = "Blacksmith status: \(current.status.label)"
                body = "Page status changed from \(previous.status.label) to \(current.status.label)."
            }
            events.append(NotificationEvent(
                id: "blackbar.status.\(previousPage).\(currentPage)",
                title: title,
                body: body,
                url: URL(string: "https://status.blacksmith.sh")
            ))
        }

        if preferences.incidents && hasStatusTransitionContext {
            let oldIDs = Set(previous.status.incidents.map(\.id))
            for incident in current.status.incidents where !oldIDs.contains(incident.id) {
                events.append(NotificationEvent(
                    id: "blackbar.incident.\(incident.id)",
                    title: "Blacksmith incident",
                    body: incident.name,
                    url: URL(string: "https://status.blacksmith.sh")
                ))
            }
        }

        if preferences.jobFinished && previous.refreshedAt != nil && current.refreshedAt != nil {
            let currentIDs = Set(current.usage.runs.map(\.id))
            var emittedRunIDs = Set<Int64>()
            for run in previous.usage.runs where !currentIDs.contains(run.id) && emittedRunIDs.insert(run.id).inserted {
                events.append(NotificationEvent(
                    id: "blackbar.job.\(run.id)",
                    title: "Job finished",
                    body: "\(run.title) on \(run.repository)",
                    url: URL(string: run.url)
                ))
            }
        }

        return events
    }
}
