import Foundation
import Testing
@testable import BlackBar

@Suite("Notification planner")
struct NotificationPlannerTests {
    private let allEnabled = NotificationPreferences(
        statusChanges: true,
        jobFinished: true,
        incidents: true
    )

    @Test("cold start is silent even when notifications are enabled")
    func coldStartIsSilent() {
        let current = snapshot(status: status("UP"), refreshedAt: Date())

        let events = NotificationPlanner.events(
            previous: .empty,
            current: current,
            preferences: allEnabled
        )

        #expect(events.isEmpty)
    }

    @Test("status transitions produce status notifications")
    func statusTransitionsNotify() {
        let previous = snapshot(status: status("UP"), refreshedAt: Date(timeIntervalSince1970: 1))
        let current = snapshot(status: status("DOWN"), refreshedAt: Date(timeIntervalSince1970: 2))

        let events = NotificationPlanner.events(
            previous: previous,
            current: current,
            preferences: allEnabled
        )

        #expect(events == [
            NotificationEvent(
                id: "blackbar.status.UP.DOWN",
                title: "Blacksmith status: DOWN",
                body: "Page status changed from All systems operational to DOWN.",
                url: URL(string: "https://status.blacksmith.sh")
            )
        ])
    }

    @Test("new incidents notify once by incident id")
    func newIncidentsNotify() {
        let existing = StatusEvent(id: "old", name: "Existing incident", status: "investigating")
        let fresh = StatusEvent(id: "new", name: "New incident", status: "investigating")
        let previous = snapshot(status: status("DOWN", incidents: [existing]), refreshedAt: Date(timeIntervalSince1970: 1))
        let current = snapshot(status: status("DOWN", incidents: [existing, fresh]), refreshedAt: Date(timeIntervalSince1970: 2))

        let events = NotificationPlanner.events(
            previous: previous,
            current: current,
            preferences: allEnabled
        )

        #expect(events == [
            NotificationEvent(
                id: "blackbar.incident.new",
                title: "Blacksmith incident",
                body: "New incident",
                url: URL(string: "https://status.blacksmith.sh")
            )
        ])
    }

    @Test("removed active runs notify as finished jobs")
    func removedRunsNotify() {
        let run = workflowRun(id: 42, repository: "steipete/BlackBar", title: "CI")
        let previous = snapshot(usage: usage(runs: [run]), refreshedAt: Date(timeIntervalSince1970: 1))
        let current = snapshot(usage: usage(runs: []), refreshedAt: Date(timeIntervalSince1970: 2))

        let events = NotificationPlanner.events(
            previous: previous,
            current: current,
            preferences: allEnabled
        )

        #expect(events == [
            NotificationEvent(
                id: "blackbar.job.42",
                title: "Job finished",
                body: "CI on steipete/BlackBar",
                url: URL(string: "https://github.com/steipete/BlackBar/actions/runs/42")
            )
        ])
    }

    @Test("reset snapshots do not mark every active job as finished")
    func resetSnapshotsAreSilentForJobs() {
        let run = workflowRun(id: 42, repository: "steipete/BlackBar", title: "CI")
        let previous = snapshot(usage: usage(runs: [run]), refreshedAt: Date(timeIntervalSince1970: 1))

        let events = NotificationPlanner.events(
            previous: previous,
            current: .empty.with(error: "Blacksmith disconnected"),
            preferences: allEnabled
        )

        #expect(events.isEmpty)
    }

    @Test("preferences gate every notification family")
    func preferencesGateEvents() {
        let previous = snapshot(
            status: status("UP"),
            usage: usage(runs: [workflowRun(id: 42, repository: "steipete/BlackBar", title: "CI")]),
            refreshedAt: Date(timeIntervalSince1970: 1)
        )
        let current = snapshot(
            status: status("DOWN", incidents: [StatusEvent(id: "new", name: "New incident", status: "investigating")]),
            usage: usage(runs: []),
            refreshedAt: Date(timeIntervalSince1970: 2)
        )

        let events = NotificationPlanner.events(
            previous: previous,
            current: current,
            preferences: NotificationPreferences(statusChanges: false, jobFinished: false, incidents: false)
        )

        #expect(events.isEmpty)
    }
}

private func snapshot(
    status: BlacksmithStatus = status("UP"),
    usage: BlacksmithUsage = usage(),
    refreshedAt: Date?
) -> DashboardSnapshot {
    DashboardSnapshot(status: status, usage: usage, refreshedAt: refreshedAt, error: nil)
}

private func status(_ pageStatus: String, incidents: [StatusEvent] = []) -> BlacksmithStatus {
    BlacksmithStatus(pageStatus: pageStatus, incidents: incidents, maintenances: [])
}

private func usage(runs: [WorkflowRunUsage] = []) -> BlacksmithUsage {
    BlacksmithUsage(
        activeVCPU: runs.reduce(0) { $0 + $1.activeVCPU },
        activeJobs: runs.reduce(0) { $0 + $1.activeJobs },
        queuedJobs: 0,
        runs: runs
    )
}

private func workflowRun(id: Int64, repository: String, title: String) -> WorkflowRunUsage {
    WorkflowRunUsage(
        id: id,
        repository: repository,
        title: title,
        workflowName: "Tests",
        url: "https://github.com/\(repository)/actions/runs/\(id)",
        activeVCPU: 1,
        activeJobs: 1,
        queuedJobs: 0,
        jobs: []
    )
}
