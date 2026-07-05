import Testing
@testable import BlackBar

@Suite("Status menu rebuild state")
struct StatusMenuRebuildStateTests {
    @Test("background snapshots skip closed menu rebuilds")
    func closedMenuSkipsSnapshotRebuild() {
        let state = StatusMenuRebuildState()

        #expect(state.shouldRebuildAfterSnapshotChange == false)
    }

    @Test("open menu snapshots rebuild visible content")
    func openMenuRebuildsForSnapshot() {
        var state = StatusMenuRebuildState()

        state.rootMenuWillOpen()
        #expect(state.shouldRebuildAfterSnapshotChange)

        state.rootMenuDidClose()
        #expect(state.shouldRebuildAfterSnapshotChange == false)
    }
}
