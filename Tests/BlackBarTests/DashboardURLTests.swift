import Foundation
import Testing
@testable import BlackBar

@Suite("Dashboard URLs")
struct DashboardURLTests {
    @Test("a plain organization opens the workflow dashboard")
    func plainOrganization() throws {
        let url = try #require(DashboardURL.blacksmithWorkflows(owner: "openclaw"))
        #expect(url.absoluteString == "https://app.blacksmith.sh/openclaw/runs/workflows")
    }

    @Test("reserved characters stay inside the organization path segment")
    func reservedCharactersStayInThePath() throws {
        let hashed = try #require(DashboardURL.blacksmithWorkflows(owner: "acme#org"))
        #expect(hashed.fragment == nil)
        #expect(hashed.absoluteString == "https://app.blacksmith.sh/acme%23org/runs/workflows")

        let queried = try #require(DashboardURL.blacksmithWorkflows(owner: "acme?org"))
        #expect(queried.query == nil)
        #expect(queried.absoluteString == "https://app.blacksmith.sh/acme%3Forg/runs/workflows")

        let slashed = try #require(DashboardURL.blacksmithWorkflows(owner: "acme/org"))
        #expect(slashed.absoluteString == "https://app.blacksmith.sh/acme%2Forg/runs/workflows")
    }

    @Test("blank organization text does not open a URL")
    func blankOrganization() {
        #expect(DashboardURL.blacksmithWorkflows(owner: " ") == nil)
        #expect(DashboardURL.blacksmithWorkflows(owner: "") == nil)
    }

    @Test("GitHub Actions encodes the organization and repository")
    func gitHubActionsEncodesPath() throws {
        let org = try #require(DashboardURL.gitHubActions(owner: "acme org", repository: ""))
        #expect(org.absoluteString == "https://github.com/orgs/acme%20org/actions")

        let repo = try #require(DashboardURL.gitHubActions(owner: "openclaw", repository: "my repo"))
        #expect(repo.absoluteString == "https://github.com/openclaw/my%20repo/actions")
    }
}
