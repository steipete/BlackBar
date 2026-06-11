import AppKit
import SwiftUI
import Testing
@testable import BlackBar

@Suite("Menu header")
struct MenuHeaderViewTests {
    @Test("incident notice grows to four lines and then caps its height")
    @MainActor
    func incidentNoticeHeightCapsAtFourLines() {
        let oneLineHeight = Self.height(incidentName: "Line one")
        let fourLineHeight = Self.height(incidentName: "Line one\nLine two\nLine three\nLine four")
        let sixLineHeight = Self.height(incidentName: "Line one\nLine two\nLine three\nLine four\nLine five\nLine six")

        #expect(fourLineHeight > oneLineHeight)
        #expect(abs(sixLineHeight - fourLineHeight) <= 1)
    }

    @MainActor
    private static func height(incidentName: String) -> CGFloat {
        let status = BlacksmithStatus(
            pageStatus: "UP",
            incidents: [StatusEvent(id: "incident", name: incidentName, status: "investigating")],
            maintenances: []
        )
        let snapshot = DashboardSnapshot(
            status: status,
            usage: BlacksmithUsage(activeVCPU: 0, activeJobs: 0, queuedJobs: 0, runs: []),
            refreshedAt: nil,
            error: nil
        )
        let controller = NSHostingController(rootView: MenuHeaderView(snapshot: snapshot, history: []))

        return controller.sizeThatFits(in: NSSize(width: 360, height: 720)).height
    }
}
