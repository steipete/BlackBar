import Foundation

struct DashboardSnapshot {
    var status: BlacksmithStatus
    var usage: BlacksmithUsage
    var refreshedAt: Date?
    var error: String?

    static let empty = DashboardSnapshot(
        status: BlacksmithStatus(pageStatus: "UNKNOWN", incidents: [], maintenances: []),
        usage: BlacksmithUsage(activeVCPU: 0, activeJobs: 0, queuedJobs: 0, runs: []),
        refreshedAt: nil,
        error: nil
    )

    var isOperational: Bool {
        status.isOperational && error == nil
    }

    func with(error: String?) -> DashboardSnapshot {
        DashboardSnapshot(status: status, usage: usage, refreshedAt: refreshedAt, error: error)
    }
}

struct BlacksmithStatus {
    var pageStatus: String
    var incidents: [StatusEvent]
    var maintenances: [StatusEvent]

    // A maintenance only affects operational state once it is actually under way.
    // Planned windows (e.g. Instatus "NOTSTARTEDYET") are announced in activeMaintenances
    // before they begin, so they stay operational while still showing the MAINT notice.
    private static func isActiveMaintenance(_ status: String) -> Bool {
        let normalized = status.uppercased().filter(\.isLetter)
        return normalized == "INPROGRESS" || normalized == "VERIFYING"
    }

    var hasActiveMaintenance: Bool {
        maintenances.contains { Self.isActiveMaintenance($0.status) }
    }

    var isOperational: Bool {
        pageStatus.uppercased() == "UP" && incidents.isEmpty && !hasActiveMaintenance
    }

    var hasActiveNotice: Bool {
        !incidents.isEmpty || !maintenances.isEmpty || pageStatus.uppercased() != "UP"
    }

    var badgeLabel: String {
        if !incidents.isEmpty { return "INCIDENT" }
        if !maintenances.isEmpty { return "MAINT" }
        let normalized = pageStatus.uppercased()
        return normalized == "UP" ? "UP" : normalized
    }

    var noticeKind: String {
        if !incidents.isEmpty { return "Incident" }
        if !maintenances.isEmpty { return "Maintenance" }
        return "Status"
    }

    var noticeTitle: String? {
        if let first = incidents.first { return first.name }
        if let first = maintenances.first { return first.name }
        return pageStatus.uppercased() == "UP" ? nil : pageStatus
    }

    var label: String {
        if isOperational {
            return "All systems operational"
        }
        if let first = incidents.first {
            return first.name
        }
        if let first = maintenances.first {
            return first.name
        }
        return pageStatus
    }
}

struct StatusEvent: Identifiable, Hashable {
    var id: String
    var name: String
    var status: String
}

struct BlacksmithUsage {
    var activeVCPU: Int
    var activeJobs: Int
    var queuedJobs: Int
    var runs: [WorkflowRunUsage]
    var recentJobs: [WorkflowRunUsage] = []
    var fetchedJobs: Int = 0
    var statusCounts: [String: Int] = [:]
    var runnerTypes: [String] = []
    var historyVCPU: [Int] = []
    var historySamples: [CoreUsageHistorySample] = []
    var workflowDistribution: [WorkflowRunDistributionBucket] = []
    var platformUsage: [String: CoreUsage] = [:]

    var debugSummary: String {
        let core = platformUsage
            .sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value.vcpus)v/\($0.value.jobs)j" }
            .joined(separator: ", ")
        guard fetchedJobs > 0 else { return core.isEmpty ? "no jobs fetched" : "core: \(core)" }
        let statuses = statusCounts
            .sorted { lhs, rhs in
                if lhs.value == rhs.value { return lhs.key < rhs.key }
                return lhs.value > rhs.value
            }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        let jobs = statuses.isEmpty ? "\(fetchedJobs) history jobs" : "\(fetchedJobs) history jobs: \(statuses)"
        return core.isEmpty ? jobs : "core: \(core); \(jobs)"
    }
}

struct CoreUsage: Codable, Hashable {
    var vcpus: Int
    var jobs: Int
}

struct CoreUsageHistorySample: Hashable {
    var amd64: CoreUsage
    var arm64: CoreUsage
    var macos: CoreUsage

    var total: CoreUsage {
        CoreUsage(
            vcpus: amd64.vcpus + arm64.vcpus + macos.vcpus,
            jobs: amd64.jobs + arm64.jobs + macos.jobs
        )
    }

    var platformUsage: [String: CoreUsage] {
        [
            "amd64": amd64,
            "arm64": arm64,
            "macos": macos
        ]
    }
}

struct WorkflowRunDistributionBucket: Identifiable, Hashable {
    var start: Date
    var end: Date
    var successCount: Int
    var failureCount: Int
    var cancelledCount: Int
    var inProgressCount: Int
    var queuedCount: Int
    var avgDurationSeconds: Double?
    var runsWithDuration: Int

    var id: Date { start }

    var totalCount: Int {
        successCount + failureCount + cancelledCount + inProgressCount + queuedCount
    }
}

struct WorkflowRunUsage: Identifiable, Hashable {
    var id: Int64
    var repository: String
    var title: String
    var workflowName: String
    var url: String
    var activeVCPU: Int
    var activeJobs: Int
    var queuedJobs: Int
    var jobs: [JobUsage]
    var status: String = ""
    var branchName: String?
    var runnerType: String?
    var runnerName: String?
    var actorLogin: String?
    var pullRequestNumber: Int?
    var pullRequestURL: String?
    var commitSHA: String?
    var commitMessage: String?
    var startedAt: Date?
    var updatedAt: Date?
    var durationSeconds: Int?
}

struct JobUsage: Identifiable, Hashable {
    var id: Int64
    var name: String
    var status: String
    var url: String?
    var vcpu: Int
    var labels: [String]
}
