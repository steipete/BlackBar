import Foundation
import Testing
@testable import BlackBar

@Suite("Job run list")
struct JobRunListDecoderTests {
    @Test("a job list that is not JSON throws")
    func invalidListThrows() {
        #expect(throws: DecodingError.self) {
            try JobRunListDecoder.count(from: Data("not-json".utf8))
        }
    }

    @Test("one job decodes")
    func oneJobDecodes() throws {
        let json = """
        [{"id":1,"name":"CI","status":"in_progress","workflow_name":"Tests","repository_name":"steipete/BlackBar","github_url":"https://github.com/steipete/BlackBar/actions/runs/1"}]
        """
        #expect(try JobRunListDecoder.count(from: Data(json.utf8)) == 1)
    }
}
