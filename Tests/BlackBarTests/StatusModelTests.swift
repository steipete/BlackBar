import Testing
@testable import BlackBar

@Suite("Blacksmith status model")
struct StatusModelTests {
    @Test("operational status stays compact")
    func operationalStatusStaysCompact() {
        let status = BlacksmithStatus(pageStatus: "UP", incidents: [], maintenances: [])

        #expect(status.hasActiveNotice == false)
        #expect(status.badgeLabel == "UP")
    }

    @Test("in-progress maintenance is not operational")
    func inProgressMaintenanceIsNotOperational() {
        let status = BlacksmithStatus(
            pageStatus: "UP",
            incidents: [],
            maintenances: [StatusEvent(id: "m1", name: "Disk replacement", status: "INPROGRESS")]
        )

        #expect(status.isOperational == false)
        #expect(status.label == "Disk replacement")
        #expect(status.badgeLabel == "MAINT")
    }

    @Test("planned maintenance stays operational but still shows a notice")
    func plannedMaintenanceStaysOperational() {
        let status = BlacksmithStatus(
            pageStatus: "UP",
            incidents: [],
            maintenances: [StatusEvent(id: "m1", name: "Disk replacement", status: "NOTSTARTEDYET")]
        )

        // A scheduled window is announced in activeMaintenances before it begins;
        // it must not flip the status dot until it is actually under way.
        #expect(status.isOperational == true)
        #expect(status.label == "All systems operational")
        #expect(status.hasActiveNotice)
        #expect(status.badgeLabel == "MAINT")
    }

    @Test("maintenance status matching ignores case and separators")
    func maintenanceStatusMatchingNormalizes() {
        let status = BlacksmithStatus(
            pageStatus: "UP",
            incidents: [],
            maintenances: [StatusEvent(id: "m1", name: "Disk replacement", status: "in_progress")]
        )

        #expect(status.isOperational == false)
    }

    @Test("incidents take badge priority")
    func incidentsTakeBadgePriority() {
        let status = BlacksmithStatus(
            pageStatus: "UP",
            incidents: [StatusEvent(id: "i1", name: "Queue delay", status: "investigating")],
            maintenances: [StatusEvent(id: "m1", name: "Maintenance", status: "scheduled")]
        )

        #expect(status.hasActiveNotice)
        #expect(status.badgeLabel == "INCIDENT")
        #expect(status.noticeKind == "Incident")
        #expect(status.noticeTitle == "Queue delay")
    }
}
