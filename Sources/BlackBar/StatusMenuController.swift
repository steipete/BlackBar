import AppKit
import SwiftUI

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private enum Metrics {
        static let menuWidth: CGFloat = 360
        static let jobsMenuWidth: CGFloat = 620
    }

    private let model: AppModel
    private let statusBar: NSStatusBar
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var timer: Timer?
    private var menuRebuildState = StatusMenuRebuildState()

    init(model: AppModel, statusBar: NSStatusBar = .system) {
        self.model = model
        self.statusBar = statusBar
        super.init()
        self.menu.autoenablesItems = false
        self.menu.delegate = self
    }

    func start() {
        let item = self.statusBar.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "blackbar-main-v2"
        item.isVisible = true
        item.button?.imageScaling = .scaleNone
        item.menu = self.menu
        self.statusItem = item

        self.model.onSnapshotChange = { [weak self] in
            self?.applyStatusItemAppearance()
            guard let self, self.menuRebuildState.shouldRebuildAfterSnapshotChange else { return }
            self.rebuildMenu()
        }
        self.model.onPollIntervalChange = { [weak self] interval in
            self?.scheduleTimer(interval: interval)
        }

        self.rebuildMenu()
        self.applyStatusItemAppearance()
        self.scheduleTimer(interval: self.model.pollInterval)
        Task { await self.model.refresh() }
    }

    func stop() {
        self.timer?.invalidate()
        self.timer = nil
        if let statusItem {
            statusItem.menu = nil
            statusItem.button?.image = nil
            self.statusBar.removeStatusItem(statusItem)
        }
        self.statusItem = nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        self.menuRebuildState.rootMenuWillOpen()
        self.rebuildMenu()
        Task { await self.model.refresh() }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        self.updateHighlights(in: menu, highlightedItem: item)
    }

    func menuDidClose(_ menu: NSMenu) {
        self.updateHighlights(in: menu, highlightedItem: nil)
        if menu === self.menu {
            self.menuRebuildState.rootMenuDidClose()
        }
    }

    @objc private func refreshNow() {
        Task { await self.model.refresh() }
    }

    @objc private func openSettings() {
        SettingsOpener.shared.open()
    }

    @objc private func installUpdate() {
        SparkleController.shared.installUpdate()
    }

    @objc private func openBlacksmith() {
        self.model.openBlacksmith()
    }

    @objc private func openBlacksmithStatus() {
        self.model.openBlacksmithStatus()
    }

    @objc private func openGitHubActions() {
        self.model.openGitHubActions()
    }

    @objc private func loginOrSignOut() {
        if self.model.authState == .disconnected {
            self.model.loginWithGitHub()
        } else {
            self.model.signOut()
        }
    }

    @objc private func openRun(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String, let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openURLString(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
        self.menu.cancelTracking()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func rebuildMenu() {
        self.menu.removeAllItems()
        self.menu.addItem(self.headerItem())
        self.menu.addItem(.separator())

        self.menu.addItem(self.disabledItem("Active: \(self.model.snapshot.usage.activeJobs) jobs, \(self.model.snapshot.usage.activeVCPU) vCPU"))
        self.menu.addItem(self.disabledItem("Queued: \(self.model.snapshot.usage.queuedJobs) jobs"))
        self.menu.addItem(self.wrappingDisabledItem("API: \(self.model.snapshot.usage.debugSummary)"))
        if let refreshedAt = self.model.snapshot.refreshedAt {
            self.menu.addItem(self.disabledItem("Updated: \(refreshedAt.formatted(date: .omitted, time: .standard))"))
        }
        if let error = self.model.snapshot.error {
            self.menu.addItem(self.wrappingDisabledItem("Error: \(error)"))
        }

        self.menu.addItem(.separator())
        self.menu.addItem(self.activeJobsItem())
        self.menu.addItem(self.actionItem("Refresh Now", action: #selector(self.refreshNow), image: "arrow.clockwise"))

        self.menu.addItem(.separator())
        self.menu.addItem(self.actionItem("Open Blacksmith", action: #selector(self.openBlacksmith), image: "hammer"))
        self.menu.addItem(self.statusActionItem())
        self.menu.addItem(self.actionItem("Open GitHub Actions", action: #selector(self.openGitHubActions), image: "arrow.up.right.square"))
        self.menu.addItem(self.actionItem(self.model.authState == .disconnected ? "Login with GitHub" : "Sign Out", action: #selector(self.loginOrSignOut), image: "person.crop.circle"))
        if SparkleController.shared.updateStatus.isUpdateReady {
            self.menu.addItem(self.actionItem("Update Ready, Restart Now?", action: #selector(self.installUpdate), image: "arrow.down.circle"))
        }
        self.menu.addItem(self.actionItem("Settings…", action: #selector(self.openSettings), image: "gearshape"))

        self.menu.addItem(.separator())
        self.menu.addItem(self.actionItem("Quit BlackBar", action: #selector(self.quit), image: "power"))
        self.refreshViewHeights(in: self.menu)
        self.menu.update()
    }

    private func headerItem() -> NSMenuItem {
        let item = NSMenuItem()
        let view = MenuItemHostingView(rootView: AnyView(MenuHeaderView(snapshot: self.model.snapshot, history: self.model.history)))
        item.view = view
        item.isEnabled = false
        return item
    }

    private func activeJobsItem() -> NSMenuItem {
        let activeJobs = self.model.snapshot.usage.activeJobs
        let title = activeJobs > 0 ? "Active Jobs (\(activeJobs))" : "Active Jobs"
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.delegate = self

        let activeRuns = self.model.snapshot.usage.runs
        let visibleRuns = activeRuns.isEmpty ? self.model.snapshot.usage.recentJobs : activeRuns

        if !visibleRuns.isEmpty {
            if activeRuns.isEmpty {
                let note = activeJobs > 0
                    ? "Active detail unavailable; latest Blacksmith jobs"
                    : "Latest Blacksmith jobs"
                submenu.addItem(self.disabledItem(note))
                submenu.addItem(.separator())
            }

            for run in visibleRuns {
                submenu.addItem(self.jobItem(for: run, isFallback: activeRuns.isEmpty))
            }
        } else {
            let activePlatforms = self.model.snapshot.usage.platformUsage
                .filter { $0.value.jobs > 0 || $0.value.vcpus > 0 }
                .sorted { lhs, rhs in
                    if lhs.value.jobs == rhs.value.jobs { return lhs.key < rhs.key }
                    return lhs.value.jobs > rhs.value.jobs
                }

            if activePlatforms.isEmpty {
                submenu.addItem(self.disabledItem("No active jobs"))
            } else {
                for (platform, usage) in activePlatforms {
                    let platformItem = self.disabledItem(
                        "\(platform): \(usage.jobs) \(Self.plural("job", usage.jobs)), \(usage.vcpus) vCPU"
                    )
                    platformItem.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)
                    submenu.addItem(platformItem)
                }
                submenu.addItem(.separator())
                submenu.addItem(self.disabledItem("Per-job detail unavailable from current API"))
            }
        }

        self.refreshViewHeights(in: submenu, width: Metrics.jobsMenuWidth)
        item.submenu = submenu
        return item
    }

    private static func plural(_ word: String, _ count: Int) -> String {
        count == 1 ? word : "\(word)s"
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func wrappingDisabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = MenuTextItemView(title: title, width: Metrics.menuWidth)
        item.isEnabled = false
        return item
    }

    private func actionItem(_ title: String, action: Selector, image: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: image, accessibilityDescription: nil)
        return item
    }

    private func statusActionItem() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.toolTip = self.model.snapshot.status.label
        let highlightState = MenuItemHighlightState()
        item.view = MenuItemHostingView(
            rootView: AnyView(
                StatusMenuActionRowView(status: self.model.snapshot.status) { [weak self] in
                    self?.model.openBlacksmithStatus()
                    self?.menu.cancelTracking()
                }
            ),
            highlightState: highlightState
        )
        return item
    }

    private func jobItem(for run: WorkflowRunUsage, isFallback: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true
        item.representedObject = run.url
        item.toolTip = self.jobTooltip(for: run)
        let highlightState = MenuItemHighlightState()
        item.view = MenuItemHostingView(
            rootView: AnyView(
                JobMenuRowView(run: run, isFallback: isFallback) { [weak self] in
                    self?.openURLString(run.url)
                }
            ),
            highlightState: highlightState
        )
        return item
    }

    private func jobTooltip(for run: WorkflowRunUsage) -> String {
        var parts = [run.repository, run.workflowName, run.title]
        if let branchName = run.branchName, !branchName.isEmpty {
            parts.append(branchName)
        }
        if let actorLogin = run.actorLogin, !actorLogin.isEmpty {
            parts.append("@\(actorLogin)")
        }
        if let commitMessage = run.commitMessage?.components(separatedBy: .newlines).first,
           !commitMessage.isEmpty
        {
            parts.append(commitMessage)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " - ")
    }

    private func applyStatusItemAppearance() {
        guard let button = self.statusItem?.button else { return }
        let image = StatusBarImage.renderGraph(
            history: self.model.history,
            active: self.model.snapshot.usage.activeVCPU
        )
        self.statusItem?.length = NSStatusItem.variableLength
        button.attributedTitle = NSAttributedString()
        button.title = self.statusTitle()
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        button.image = image
        button.imagePosition = .imageRight
        button.toolTip = "BlackBar: \(self.model.snapshot.usage.activeVCPU) active vCPU, \(self.model.snapshot.usage.activeJobs) active jobs"
    }

    private func statusTitle() -> String {
        let needsStatusDot = self.model.snapshot.isOperational == false
        let title = "\(self.model.snapshot.usage.activeVCPU)"
        return needsStatusDot ? "● \(title)" : title
    }

    private func scheduleTimer(interval: TimeInterval) {
        self.timer?.invalidate()
        self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.model.refresh()
            }
        }
    }

    private func refreshViewHeights(in menu: NSMenu, width: CGFloat = Metrics.menuWidth) {
        for item in menu.items {
            guard let view = item.view, let measuring = view as? MenuItemMeasuring else { continue }
            let height = measuring.measuredHeight(width: width)
            view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        }
    }

    private func updateHighlights(in menu: NSMenu, highlightedItem: NSMenuItem?) {
        for item in menu.items {
            guard let highlighting = item.view as? MenuItemHighlighting else { continue }
            highlighting.setHighlighted(item === highlightedItem && item.isEnabled)
        }
    }
}

struct StatusMenuRebuildState {
    private(set) var isRootMenuOpen = false

    var shouldRebuildAfterSnapshotChange: Bool {
        self.isRootMenuOpen
    }

    mutating func rootMenuWillOpen() {
        self.isRootMenuOpen = true
    }

    mutating func rootMenuDidClose() {
        self.isRootMenuOpen = false
    }
}

@MainActor
private final class MenuTextItemView: NSView, MenuItemMeasuring {
    private enum Metrics {
        static let horizontalInset: CGFloat = 14
        static let verticalInset: CGFloat = 4
    }

    private let textField = NSTextField(labelWithString: "")

    override var allowsVibrancy: Bool {
        true
    }

    init(title: String, width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 24))
        self.textField.stringValue = title
        self.textField.font = .menuFont(ofSize: 0)
        self.textField.textColor = .disabledControlTextColor
        self.textField.lineBreakMode = .byWordWrapping
        self.textField.maximumNumberOfLines = 0
        self.textField.cell?.wraps = true
        self.addSubview(self.textField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        self.textField.frame = self.labelFrame(width: self.bounds.width, height: self.bounds.height)
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        let labelWidth = width - Metrics.horizontalInset * 2
        let boundingSize = NSSize(width: labelWidth, height: .greatestFiniteMagnitude)
        let measured = self.textField.cell?.cellSize(forBounds: NSRect(origin: .zero, size: boundingSize)).height
            ?? self.textField.intrinsicContentSize.height
        return ceil(measured + Metrics.verticalInset * 2)
    }

    private func labelFrame(width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(
            x: Metrics.horizontalInset,
            y: Metrics.verticalInset,
            width: width - Metrics.horizontalInset * 2,
            height: height - Metrics.verticalInset * 2
        )
    }
}
