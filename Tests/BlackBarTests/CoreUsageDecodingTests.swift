import Foundation
import Testing
@testable import BlackBar

@Suite("Core usage decoding")
struct CoreUsageDecodingTests {
    @Test("current usage can be null")
    func currentUsageCanBeNull() throws {
        let data = Data(#"{"current_usage":null}"#.utf8)

        let snapshot = try CoreUsagePayloadDecoder.currentSnapshot(from: data)

        #expect(snapshot.total == CoreUsage(vcpus: 0, jobs: 0))
    }

    @Test("current usage can be an empty body")
    func currentUsageCanBeEmptyBody() throws {
        let snapshot = try CoreUsagePayloadDecoder.currentSnapshot(from: Data())

        #expect(snapshot.total == CoreUsage(vcpus: 0, jobs: 0))
    }

    @Test("current usage can be a top-level null body")
    func currentUsageCanBeTopLevelNullBody() throws {
        let snapshot = try CoreUsagePayloadDecoder.currentSnapshot(from: Data(" null\n".utf8))

        #expect(snapshot.total == CoreUsage(vcpus: 0, jobs: 0))
    }

    @Test("timeseries tolerates null usage points")
    func timeseriesToleratesNullUsagePoints() throws {
        let data = Data(#"{"timeseries":[{"usage":null},{"usage":{"amd64":{"vcpus":2,"jobs":1},"arm64":null,"macos":{"vcpus":0,"jobs":0}}}]}"#.utf8)

        let response = try JSONDecoder().decode(CoreUsageTimeseriesResponse.self, from: data)

        #expect(response.timeseries.count == 2)
        #expect(response.timeseries[0].usage == nil)
        #expect(response.timeseries[1].usage?.amd64 == CoreUsage(vcpus: 2, jobs: 1))
        #expect(response.timeseries[1].usage?.arm64 == CoreUsage(vcpus: 0, jobs: 0))
    }

    @Test("timeseries preserves null usage points as zero samples")
    func timeseriesPreservesNullUsagePointsAsZeroSamples() throws {
        let data = Data(#"{"timeseries":[{"usage":null},{"usage":{"amd64":{"vcpus":2,"jobs":1},"arm64":null,"macos":{"vcpus":0,"jobs":0}}}]}"#.utf8)

        let snapshots = try CoreUsagePayloadDecoder.timeseriesSnapshots(from: data)

        #expect(snapshots.count == 2)
        #expect(snapshots[0].total == CoreUsage(vcpus: 0, jobs: 0))
        #expect(snapshots[1].total == CoreUsage(vcpus: 2, jobs: 1))
    }

    @Test("timeseries can be an empty body")
    func timeseriesCanBeEmptyBody() throws {
        let snapshots = try CoreUsagePayloadDecoder.timeseriesSnapshots(from: Data())

        #expect(snapshots.isEmpty)
    }

    @Test("timeseries can be a top-level null body")
    func timeseriesCanBeTopLevelNullBody() throws {
        let snapshots = try CoreUsagePayloadDecoder.timeseriesSnapshots(from: Data("null".utf8))

        #expect(snapshots.isEmpty)
    }

    @Test("workflow histogram decodes distribution buckets")
    func workflowHistogramDecodesDistributionBuckets() throws {
        let data = Data("""
        {"buckets":[{"start":"2026-05-15T13:10:00.123Z","end":"2026-05-15T14:10:02Z","success_count":1662,"failure_count":107,"cancelled_count":845,"in_progress_count":2,"queued_count":3,"total_count":2619,"avg_duration_seconds":48.575,"runs_with_duration":3721}]}
        """.utf8)

        let buckets = try WorkflowRunHistogramDecoder.buckets(from: data)

        #expect(buckets.count == 1)
        #expect(buckets[0].successCount == 1662)
        #expect(buckets[0].failureCount == 107)
        #expect(buckets[0].cancelledCount == 845)
        #expect(buckets[0].inProgressCount == 2)
        #expect(buckets[0].queuedCount == 3)
        #expect(buckets[0].totalCount == 2619)
        #expect(buckets[0].avgDurationSeconds == 48.575)
    }

    @Test("workflow histogram can be an empty body")
    func workflowHistogramCanBeEmptyBody() throws {
        let buckets = try WorkflowRunHistogramDecoder.buckets(from: Data())

        #expect(buckets.isEmpty)
    }
}
