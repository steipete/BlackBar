# Vision

BlackBar makes Blacksmith's current operational state and live runner load
glanceable from the macOS menu bar. It should answer "is the service healthy?"
and "what is running?" without opening a dashboard or creating another service
between the user and Blacksmith.

## Product principles

- **Native and quiet.** Keep the app small, fast, menu-bar-first, and useful at
  a glance. Prefer focused status and action over dashboard-sized UI.
- **Truthful right now.** Present current operational impact accurately. Future
  maintenance may remain operational until it starts; active maintenance or an
  incident must not be described as fully operational.
- **Local-first privacy.** Talk only to Blacksmith's public status feed and the
  signed-in Blacksmith dashboard. Keep credentials in Keychain. Do not add
  telemetry, proxy services, crash-reporting services, or background data sync.
- **Narrow scope.** Show service health, active workload, useful history, and
  tightly related notifications or actions. Do not grow into a general-purpose
  CI dashboard or workflow manager.
- **Shippable reliability.** Preserve signed, notarized, automatically updated
  builds. Fail clearly when authentication or upstream data is unavailable, and
  keep release and update tooling reproducible.

## Decision rule

Prefer changes that reduce time-to-understand or time-to-action without adding
new infrastructure, persistent data, or visual noise. New network destinations,
new data retention, or a material expansion beyond status and live workload
require an explicit product decision.
