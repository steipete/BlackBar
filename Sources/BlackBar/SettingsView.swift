import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedTab = SettingsTab.general
    @State private var contentWidth = SettingsTab.general.preferredWidth
    @State private var contentHeight = SettingsTab.general.preferredHeight

    var body: some View {
        TabView(selection: self.$selectedTab) {
            GeneralSettingsView(model: self.model)
                .tabItem { Label("General", systemImage: "gear") }
                .tag(SettingsTab.general)
            DashboardSettingsView(model: self.model)
                .tabItem { Label("Dashboard", systemImage: "chart.bar.xaxis") }
                .tag(SettingsTab.dashboard)
            NotificationsSettingsView(model: self.model)
                .tabItem { Label("Notifications", systemImage: "bell") }
                .tag(SettingsTab.notifications)
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: self.contentWidth, height: self.contentHeight)
        .onAppear {
            self.updateLayout(for: self.selectedTab, animate: false)
        }
        .onChange(of: self.selectedTab) { _, tab in
            self.updateLayout(for: tab, animate: true)
        }
    }

    private func updateLayout(for tab: SettingsTab, animate: Bool) {
        let change = {
            self.contentWidth = tab.preferredWidth
            self.contentHeight = tab.preferredHeight
        }
        if animate {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { change() }
        } else {
            change()
        }
        Self.resizeSettingsWindow(width: tab.preferredWidth, height: tab.preferredHeight, animate: animate)
    }

    private static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"
    private static let knownTabTitles = Set(SettingsTab.allCases.map(\.title))

    private static func resizeSettingsWindow(width: CGFloat, height: CGFloat, animate: Bool) {
        guard let window = NSApp.windows.first(where: {
            $0.identifier?.rawValue == self.settingsWindowIdentifier || self.knownTabTitles.contains($0.title)
        }) else { return }

        let toolbarHeight = window.frame.height - window.contentLayoutRect.height
        guard toolbarHeight > 0 else { return }

        let newSize = NSSize(width: width, height: height + toolbarHeight)
        var frame = window.frame
        frame.origin.y += frame.size.height - newSize.height
        frame.size = newSize
        window.setFrame(frame, display: true, animate: animate)
    }
}

enum SettingsTab: CaseIterable, Hashable {
    case general
    case dashboard
    case notifications
    case about

    static let defaultWidth: CGFloat = 540
    static let dashboardWidth: CGFloat = 620
    static let windowHeight: CGFloat = 473

    var title: String {
        switch self {
        case .general: "General"
        case .dashboard: "Dashboard"
        case .notifications: "Notifications"
        case .about: "About"
        }
    }

    var preferredWidth: CGFloat {
        self == .dashboard ? Self.dashboardWidth : Self.defaultWidth
    }

    var preferredHeight: CGFloat {
        Self.windowHeight
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Blacksmith") {
                TextField("GitHub organization", text: self.$model.owner)
                TextField("Repository filter", text: self.$model.repoFilter)
                Picker("Refresh interval", selection: self.$model.pollInterval) {
                    Text("30 seconds").tag(TimeInterval(30))
                    Text("1 minute").tag(TimeInterval(60))
                    Text("2 minutes").tag(TimeInterval(120))
                    Text("5 minutes").tag(TimeInterval(300))
                }
            }

            Section("Startup") {
                Toggle("Launch BlackBar at login", isOn: self.$model.launchAtLoginEnabled)
                if let note = self.model.launchAtLoginStatusNote {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Account") {
                LabeledContent("Status", value: self.model.authState.label)
                HStack {
                    Button(self.model.authState == .disconnected ? "Login with GitHub" : "Sign Out") {
                        if self.model.authState == .disconnected {
                            self.model.loginWithGitHub()
                        } else {
                            self.model.signOut()
                        }
                    }
                    Button("Refresh Now") {
                        Task { await self.model.refresh() }
                    }
                    .disabled(self.model.isRefreshing)
                }
            }

            Section("Open") {
                HStack {
                    Button("Blacksmith Dashboard") {
                        self.model.openBlacksmith()
                    }
                    Button("GitHub Actions") {
                        self.model.openGitHubActions()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear {
            self.model.refreshLaunchAtLoginState()
        }
    }
}

private struct DashboardSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(self.model.snapshot.usage.activeVCPU)")
                    .font(.system(size: 42, weight: .semibold, design: .monospaced))
                Text("active vCPU")
                    .foregroundStyle(.secondary)
                Spacer()
                Sparkline(values: self.model.history)
                    .frame(width: 180, height: 46)
            }

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
                GridRow {
                    Text("Status")
                    Text(self.model.snapshot.status.label)
                        .foregroundStyle(self.model.snapshot.isOperational ? .green : .orange)
                }
                GridRow {
                    Text("Active jobs")
                    Text("\(self.model.snapshot.usage.activeJobs)")
                }
                GridRow {
                    Text("Queued")
                    Text("\(self.model.snapshot.usage.queuedJobs)")
                }
                GridRow {
                    Text("API sample")
                    Text(self.model.snapshot.usage.debugSummary)
                }
                if !self.model.snapshot.usage.runnerTypes.isEmpty {
                    GridRow {
                        Text("Runner types")
                        Text(self.model.snapshot.usage.runnerTypes.prefix(5).joined(separator: ", "))
                            .lineLimit(2)
                    }
                }
                if let refreshedAt = self.model.snapshot.refreshedAt {
                    GridRow {
                        Text("Updated")
                        Text(refreshedAt.formatted(date: .omitted, time: .standard))
                    }
                }
                if let error = self.model.snapshot.error {
                    GridRow {
                        Text("Error")
                        Text(error).foregroundStyle(.orange)
                    }
                }
            }
            .font(.callout)

            List(self.model.snapshot.usage.runs) { run in
                HStack {
                    Text("\(run.activeVCPU)")
                        .font(.body.monospacedDigit().weight(.semibold))
                        .frame(width: 34, alignment: .trailing)
                    VStack(alignment: .leading) {
                        Text(run.title).lineLimit(1)
                        Text("\(run.repository) · \(run.workflowName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .overlay {
                if self.model.snapshot.usage.runs.isEmpty {
                    ContentUnavailableView("No active Blacksmith jobs", systemImage: "checkmark.circle")
                }
            }
        }
        .padding(20)
    }
}

private struct NotificationsSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("Send notifications when") {
                Toggle("Blacksmith status changes", isOn: self.$model.notifyStatusChanges)
                Toggle("A new incident is reported", isOn: self.$model.notifyIncidents)
                Toggle("A tracked job finishes", isOn: self.$model.notifyJobFinished)
            }

            Section {
                Text("Click a notification to open the relevant Blacksmith or GitHub page. Notifications are off by default; turning one on prompts macOS for permission.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Send Test Notification") {
                    Task { await Notifications.shared.sendTestNotification() }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

private struct AboutSettingsView: View {
    @AppStorage("autoUpdateEnabled") private var autoUpdateEnabled = true
    @State private var didSyncUpdater = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cpu")
                .font(.system(size: 42))
            Text("BlackBar")
                .font(.title2.weight(.semibold))
            Text("Blacksmith status and active vCPU in the macOS menu bar.")
                .foregroundStyle(.secondary)
            Text("0.1.0")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()
                .padding(.vertical, 8)

            if SparkleController.shared.canCheckForUpdates {
                Toggle("Check for updates automatically", isOn: self.$autoUpdateEnabled)
                    .toggleStyle(.checkbox)
                Button("Check for Updates…") {
                    SparkleController.shared.checkForUpdates()
                }
            } else {
                Text("Updates unavailable in this build.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
        .onAppear {
            guard !self.didSyncUpdater else { return }
            if SparkleController.shared.canCheckForUpdates {
                SparkleController.shared.automaticallyChecksForUpdates = self.autoUpdateEnabled
                SparkleController.shared.automaticallyDownloadsUpdates = self.autoUpdateEnabled
            }
            self.didSyncUpdater = true
        }
        .onChange(of: self.autoUpdateEnabled) { _, newValue in
            if SparkleController.shared.canCheckForUpdates {
                SparkleController.shared.automaticallyChecksForUpdates = newValue
                SparkleController.shared.automaticallyDownloadsUpdates = newValue
            }
        }
    }
}
