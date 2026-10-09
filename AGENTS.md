# Contributor guidance

DockGlass makes SwiftUI glass render like the macOS Dock and Cmd-Tab switcher by tuning the
private `glassBackground` filter behind SwiftUI's `.clear` glass. Everything it relies on is
undocumented, so treat every value as measured, not designed.

## Rules

- Override only the inputs in `GlassTuning.Input`. The system owns every other input, including
  the frosted fill driven by the Liquid Glass tint setting; overriding those would break it.
- Never apply tuning when Reduce Transparency or Increase Contrast is on, on an unverified macOS
  major version, or when the filter lacks a required input. Fall back to stock `.clear` glass and
  report the reason through `DockGlass.status`.
- The `filters` observer must write only when a value differs and must not re-enter: writing an
  input re-posts `filters`, and an unguarded handler recurses until it crashes.
- New tuning values come from `glass-fit`, scored against native captures. Record the backdrops,
  appearance, tint and macOS build they were fitted on next to the table.
- Captures that show a contributor's own apps or windows never go in the repository; regenerate
  media with stock apps.

## Verify

`swift test` renders real glass off-screen and reads filter values back. It needs a logged-in
window server but not Screen Recording. Mutation-check new guard logic: disable it and confirm a
test fails.
