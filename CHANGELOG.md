# Changelog

## 0.2.5 - Unreleased

- Treat an in-progress maintenance window as not operational, so the status stops reading "All systems operational" while the badge shows "MAINT". Planned maintenance announced ahead of time stays operational until it actually starts. Thanks @devYRPauli.
- Keep the website download buttons pointed at the latest GitHub release instead of a hard-coded older version.

## 0.2.4 - 2026-06-12

- Show active status details below the Blacksmith Status action, wrapping across up to four lines.

## 0.2.3 - 2026-06-11

- Remove temporary App Store Connect key material when notarization key conversion fails.

## 0.2.2 - 2026-05-22

- Add right-click PNG export from the menu graphs, including labeled vCPU and workflow-run snapshots (#2). Thanks @mvanhorn.
- Clarify Sparkle signing key ownership and validate release signing keys against the embedded public key.

## 0.2.1 - 2026-05-21

- Add a General setting to launch BlackBar automatically at login.
- Move Blacksmith account status, login actions, and account links into a dedicated Account settings tab.
- Store the launch-at-login preference and apply it at startup instead of showing a false unavailable state in local builds.
- Show the app version from bundle metadata in the About settings pane.
- Document the Homebrew cask install command in the README.

## 0.2.0 - 2026-05-16

- Add opt-in macOS notifications for Blacksmith status changes, new incidents, and finished jobs (#1). Thanks @mvanhorn.
- Add a menu link to the public Blacksmith status page.
- Treat empty or null Blacksmith core-usage API responses as zero usage instead of showing a decode error.
- Show a stacked 24-hour vCPU usage chart with platform buckets and peak/average stats in the menu.
- Show a separate Blacksmith workflow run distribution chart with hover details below the vCPU chart.
- Show richer SwiftUI Blacksmith job rows with branch, actor, PR, runner, commit, and timing details.
- Move the Blacksmith status indicator into a compact status-page menu badge unless there is an active notice.
- Keep the menu bar title compact while including active job count in the tooltip and menu.
- Only show the menu update action once a Sparkle update is ready to install.

## 0.1.3 - 2026-05-10

- Move GitHub release, appcast, documentation, and update-feed references to `steipete/BlackBar`.

## 0.1.2 - 2026-05-10

- Restore native macOS status item tinting by using a template graph image and plain status button title, so menu bar text and graph adapt correctly across light, dark, and tinted backgrounds.

## 0.1.1 - 2026-05-10

- Use high-contrast menu bar text and graph rendering for bright Blacksmith-style desktop backgrounds.
- Remove the duplicate status line from the menu details.
- Replace the app icon artwork with a full-bleed Blacksmith-style neon tile that avoids the white inset gap in Finder and Launchpad.

## 0.1.0 - 2026-05-10

- Add the initial native macOS menu bar app for Blacksmith CI status and live vCPU usage.
- Show current Blacksmith vCPU and active job totals in the menu bar with a compact history graph.
- Add an AppKit-native menu with public Blacksmith status, active and queued counts, API diagnostics, manual refresh, and direct links to Blacksmith and GitHub Actions.
- Show live platform buckets for `amd64`, `arm64`, and `macos` usage when per-job details are not available.
- Add GitHub login through Blacksmith's OAuth flow in a native WebKit window.
- Store the Blacksmith session cookie in Keychain and cache it in memory after launch to avoid repeated Keychain prompts.
- Add a native Settings window for organization, repository filter, and polling interval.
- Add dynamic menu bar sizing for large vCPU counts and fixed-width wrapped diagnostics in the menu.
- Add a Blacksmith-inspired macOS app icon with neon yellow, blocky black glyphs, and vCPU activity bars.
- Add Sparkle-based automatic updates for signed release builds.
- Add release packaging, codesigning, notarization, appcast, release-note helpers, live-update testing, and macOS CI.
