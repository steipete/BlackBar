import Foundation

struct BlacksmithDashboardClient {
    private let baseURL = URL(string: "https://dashboardbackend.blacksmith.sh/api")!
    private let cookieHeader: String
    private static let fractionalISO8601 = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSecondISO8601 = Date.ISO8601FormatStyle()

    init(cookieHeader: String) {
        self.cookieHeader = cookieHeader
    }

    func fetchUser() async throws -> BlacksmithUser {
        let data = try await request(path: "user")
        return try JSONDecoder().decode(BlacksmithUser.self, from: data)
    }

    func fetchUsage(owner: String, repoFilter: String) async throws -> BlacksmithUsage {
        let end = Date()
        let historyStart = end.addingTimeInterval(-24 * 60 * 60)

        async let currentCoreUsage = fetchCurrentCoreUsage(owner: owner)
        async let coreUsageSamples = fetchCoreUsageTimeseries(owner: owner)
        let repoNeedle = repoFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // The histogram endpoint is org-wide, so hide it when the rest of the view is repo-scoped.
        async let workflowDistribution: [WorkflowRunDistributionBucket] = repoNeedle.isEmpty
            ? fetchWorkflowRunDistribution(owner: owner, start: historyStart, end: end)
            : []
        let core = try await currentCoreUsage
        let samples = (try? await coreUsageSamples) ?? []
        let distribution = (try? await workflowDistribution) ?? []

        let start = end.addingTimeInterval(-12 * 60 * 60)
        var components = URLComponents(url: baseURL.appending(path: "user/github/orgs/\(owner)/metrics/actions/jobs/runs"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: Self.isoString(from: start)),
            URLQueryItem(name: "end_date", value: Self.isoString(from: end)),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let jobs = (try? JSONDecoder().decode([BlacksmithJobRun].self, from: try await request(url: url))) ?? []
        let relevantJobs = jobs.filter { job in
            guard !repoNeedle.isEmpty else { return true }
            let repo = job.repositoryName.lowercased()
            return repo == repoNeedle || repo.hasSuffix("/\(repoNeedle)")
        }

        let active = relevantJobs.filter { $0.status.normalizedRunStatus == "in_progress" }
        let queued = relevantJobs.filter { $0.status.normalizedRunStatus == "queued" }
        let statusCounts = Dictionary(grouping: relevantJobs, by: { $0.status.normalizedRunStatus })
            .mapValues(\.count)
        let runnerTypes = Array(Set(relevantJobs.compactMap(\.runnerType))).sorted()
        let activeRuns = active.prefix(20).map(Self.workflowRun)
        let recentJobs = relevantJobs.prefix(20).map(Self.workflowRun)

        return BlacksmithUsage(
            activeVCPU: core.total.vcpus,
            activeJobs: core.total.jobs,
            queuedJobs: queued.count,
            runs: Array(activeRuns),
            recentJobs: Array(recentJobs),
            fetchedJobs: relevantJobs.count,
            statusCounts: statusCounts,
            runnerTypes: runnerTypes,
            historyVCPU: samples.map(\.total.vcpus),
            historySamples: samples.map(\.historySample),
            workflowDistribution: distribution,
            platformUsage: core.platformUsage
        )
    }

    private static func workflowRun(from job: BlacksmithJobRun) -> WorkflowRunUsage {
        WorkflowRunUsage(
            id: job.id,
            repository: job.repositoryName,
            title: job.name,
            workflowName: job.workflowName,
            url: job.githubURL,
            activeVCPU: job.vcpu,
            activeJobs: job.status.normalizedRunStatus == "in_progress" ? 1 : 0,
            queuedJobs: job.status.normalizedRunStatus == "queued" ? 1 : 0,
            jobs: [
                JobUsage(
                    id: job.id,
                    name: job.name,
                    status: job.status,
                    url: job.githubURL,
                    vcpu: job.vcpu,
                    labels: [job.runnerType ?? "unknown"]
                )
            ],
            status: job.status,
            branchName: job.branchName,
            runnerType: job.runnerType,
            runnerName: job.runnerName,
            actorLogin: job.actor?.login,
            pullRequestNumber: job.pullRequest?.number,
            pullRequestURL: job.pullRequest?.htmlURL,
            commitSHA: job.headCommit?.sha,
            commitMessage: job.headCommit?.message,
            startedAt: Self.date(from: job.startedAt),
            updatedAt: Self.date(from: job.updatedAt),
            durationSeconds: job.durationSeconds
        )
    }

    private func request(path: String) async throws -> Data {
        try await request(url: baseURL.appending(path: path))
    }

    private func request(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://app.blacksmith.sh", forHTTPHeaderField: "Origin")
        request.setValue("https://app.blacksmith.sh/", forHTTPHeaderField: "Referer")
        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTP.validate(response: response, data: data)
        return data
    }

    private func fetchCurrentCoreUsage(owner: String) async throws -> CoreUsageSnapshot {
        let data = try await request(path: "user/github/orgs/\(owner)/metrics/core-usage/current")
        return try CoreUsagePayloadDecoder.currentSnapshot(from: data)
    }

    private func fetchCoreUsageTimeseries(owner: String) async throws -> [CoreUsageSnapshot] {
        let end = Date()
        let start = end.addingTimeInterval(-24 * 60 * 60)
        var components = URLComponents(url: baseURL.appending(path: "user/github/orgs/\(owner)/metrics/core-usage/timeseries"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "window_size", value: "15"),
            URLQueryItem(name: "start_date", value: Self.isoString(from: start)),
            URLQueryItem(name: "end_date", value: Self.isoString(from: end))
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        return try CoreUsagePayloadDecoder.timeseriesSnapshots(from: try await request(url: url))
    }

    private func fetchWorkflowRunDistribution(owner: String, start: Date, end: Date) async throws -> [WorkflowRunDistributionBucket] {
        var components = URLComponents(url: baseURL.appending(path: "user/github/orgs/\(owner)/metrics/actions/workflows/runs/histogram"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: Self.isoString(from: start)),
            URLQueryItem(name: "end_date", value: Self.isoString(from: end)),
            URLQueryItem(name: "bucket_count", value: "24")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        return try WorkflowRunHistogramDecoder.buckets(from: try await request(url: url))
    }

    private static func isoString(from date: Date) -> String {
        date.formatted(Self.fractionalISO8601)
    }

    fileprivate static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        return (try? Self.fractionalISO8601.parse(string))
            ?? (try? Self.wholeSecondISO8601.parse(string))
    }
}

struct CoreUsageSnapshot {
    var amd64: CoreUsage
    var arm64: CoreUsage
    var macos: CoreUsage

    init(usage: CoreUsageResponse) {
        amd64 = usage.amd64
        arm64 = usage.arm64
        macos = usage.macos
    }

    static let empty = CoreUsageSnapshot(
        usage: CoreUsageResponse(amd64: .zero, arm64: .zero, macos: .zero)
    )

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

    var historySample: CoreUsageHistorySample {
        CoreUsageHistorySample(amd64: amd64, arm64: arm64, macos: macos)
    }
}

enum CoreUsagePayloadDecoder {
    static func currentSnapshot(from data: Data) throws -> CoreUsageSnapshot {
        guard !isEmptyOrNull(data) else { return .empty }
        let response = try JSONDecoder().decode(CoreUsageCurrentResponse.self, from: data)
        return response.currentUsage.map(CoreUsageSnapshot.init(usage:)) ?? .empty
    }

    static func timeseriesSnapshots(from data: Data) throws -> [CoreUsageSnapshot] {
        guard !isEmptyOrNull(data) else { return [] }
        let response = try JSONDecoder().decode(CoreUsageTimeseriesResponse.self, from: data)
        return response.timeseries.map { $0.usage.map(CoreUsageSnapshot.init(usage:)) ?? .empty }
    }

    fileprivate static func isEmptyOrNull(_ data: Data) -> Bool {
        data.isEmpty || String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "null"
    }
}

enum WorkflowRunHistogramDecoder {
    static func buckets(from data: Data) throws -> [WorkflowRunDistributionBucket] {
        guard !CoreUsagePayloadDecoder.isEmptyOrNull(data) else { return [] }
        let response = try JSONDecoder().decode(WorkflowRunHistogramResponse.self, from: data)
        return response.buckets.compactMap { bucket in
            guard let start = BlacksmithDashboardClient.date(from: bucket.start),
                  let end = BlacksmithDashboardClient.date(from: bucket.end)
            else { return nil }
            return WorkflowRunDistributionBucket(
                start: start,
                end: end,
                successCount: bucket.successCount,
                failureCount: bucket.failureCount,
                cancelledCount: bucket.cancelledCount,
                inProgressCount: bucket.inProgressCount,
                queuedCount: bucket.queuedCount,
                avgDurationSeconds: bucket.avgDurationSeconds,
                runsWithDuration: bucket.runsWithDuration
            )
        }
    }
}

struct CoreUsageCurrentResponse: Decodable {
    var currentUsage: CoreUsageResponse?

    enum CodingKeys: String, CodingKey {
        case currentUsage = "current_usage"
    }
}

private struct WorkflowRunHistogramResponse: Decodable {
    var buckets: [WorkflowRunHistogramBucket]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        buckets = try container.decodeIfPresent([WorkflowRunHistogramBucket].self, forKey: .buckets) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case buckets
    }
}

private struct WorkflowRunHistogramBucket: Decodable {
    var start: String
    var end: String
    var successCount: Int
    var failureCount: Int
    var cancelledCount: Int
    var inProgressCount: Int
    var queuedCount: Int
    var avgDurationSeconds: Double?
    var runsWithDuration: Int

    enum CodingKeys: String, CodingKey {
        case start
        case end
        case successCount = "success_count"
        case failureCount = "failure_count"
        case cancelledCount = "cancelled_count"
        case inProgressCount = "in_progress_count"
        case queuedCount = "queued_count"
        case avgDurationSeconds = "avg_duration_seconds"
        case runsWithDuration = "runs_with_duration"
    }
}

struct CoreUsageTimeseriesResponse: Decodable {
    var timeseries: [CoreUsageTimeseriesPoint]

    enum CodingKeys: String, CodingKey {
        case timeseries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeseries = try container.decodeIfPresent([CoreUsageTimeseriesPoint].self, forKey: .timeseries) ?? []
    }
}

struct CoreUsageTimeseriesPoint: Decodable {
    var usage: CoreUsageResponse?
}

struct CoreUsageResponse: Decodable {
    var amd64: CoreUsage
    var arm64: CoreUsage
    var macos: CoreUsage

    enum CodingKeys: String, CodingKey {
        case amd64
        case arm64
        case macos
    }

    init(amd64: CoreUsage, arm64: CoreUsage, macos: CoreUsage) {
        self.amd64 = amd64
        self.arm64 = arm64
        self.macos = macos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        amd64 = try container.decodeIfPresent(CoreUsage.self, forKey: .amd64) ?? .zero
        arm64 = try container.decodeIfPresent(CoreUsage.self, forKey: .arm64) ?? .zero
        macos = try container.decodeIfPresent(CoreUsage.self, forKey: .macos) ?? .zero
    }
}

private extension CoreUsage {
    static let zero = CoreUsage(vcpus: 0, jobs: 0)
}

struct BlacksmithUser: Decodable {
    var id: Int?
    var name: String?
    var email: String?
    var username: String?
}

private struct BlacksmithJobRun: Decodable {
    var id: Int64
    var name: String
    var status: String
    var workflowName: String
    var repositoryName: String
    var githubURL: String
    var runnerType: String?
    var title: String?
    var branchName: String?
    var runnerName: String?
    var actor: BlacksmithActor?
    var pullRequest: BlacksmithPullRequest?
    var headCommit: BlacksmithHeadCommit?
    var startedAt: String?
    var updatedAt: String?
    var durationSeconds: Int?

    var vcpu: Int {
        RunnerLabel.vcpu(from: runnerType ?? "")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case workflowName = "workflow_name"
        case repositoryName = "repository_name"
        case githubURL = "github_url"
        case runnerType = "runner_type"
        case title
        case branchName = "branch_name"
        case runnerName = "runner_name"
        case actor
        case pullRequest = "pull_request"
        case headCommit = "head_commit"
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case durationSeconds = "duration_seconds"
    }
}

private struct BlacksmithActor: Decodable {
    var login: String?
}

private struct BlacksmithPullRequest: Decodable {
    var number: Int?
    var htmlURL: String?

    enum CodingKeys: String, CodingKey {
        case number
        case htmlURL = "html_url"
    }
}

private struct BlacksmithHeadCommit: Decodable {
    var sha: String?
    var message: String?
}

enum RunnerLabel {
    static func vcpu(from label: String) -> Int {
        let lower = label.lowercased()
        guard let range = lower.range(of: #"(\d+)vcpu"#, options: .regularExpression) else {
            return lower.contains("blacksmith") ? 2 : 0
        }
        let digits = lower[range].prefix { $0.isNumber }
        return Int(digits) ?? 0
    }
}

private extension String {
    var normalizedRunStatus: String {
        lowercased().replacingOccurrences(of: "-", with: "_")
    }
}
