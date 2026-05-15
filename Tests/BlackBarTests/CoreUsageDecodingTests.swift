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
}
