# Contributor guidance

DockGlass makes SwiftUI glass render like the macOS Dock and Cmd-Tab switcher. On macOS 27 it
draws SwiftUI's private Dock glass in the active window state and tunes the private
`glassBackground` filter behind it; macOS 26's look tunes `.clear` glass drawn inactive.
Everything it relies on is undocumented, so treat every value as measured, not designed.

## Rules

- Override only the inputs in `GlassTuning.Input`, the inputs `TintResponse` drives and the
  properties in `GlassHighlight.Property`. The system owns everything else. Leave an input out of
  a look when the system's value already matches native; macOS 27's look overrides only the edge
  band.
- Fit in the focus state the native switcher draws in. Glass in a never-activated panel draws
  inactive, and a fit made there compensates for the wrong state (Docs/FINDINGS.md). Record the
  state with the look (`GlassLook.fittedFocus`).
- Change the rim's effect by assigning a modified copy; in-place changes never render. Hide it
  through its colours' alpha, never an amount or height of 0, which draw a solid band.
- Never apply tuning when Reduce Transparency or Increase Contrast is on, on an unverified macOS
  major version, or when the filter lacks a required input. Fall back to stock `.clear` glass and
  report the reason through `DockGlass.status`.
- The `filters` and `effect` observers must write only when a value differs and must not
  re-enter: writing re-posts the property, and an unguarded handler recurses until it crashes.
- Look up private SwiftUI symbols at run time and check they behave before use; a missing one
  falls back to stock glass with a `DockGlass.Reason`, never a launch failure.
- New tuning values come from `glass-fit`, scored against native captures. Record the backdrops,
  appearance, tint and macOS build they were fitted on next to the table.
- Captures that show a contributor's own apps or windows never go in the repository; regenerate
  media with stock apps.

## Verify

`swift test` renders real glass off-screen and reads filter and rim values back; the off-screen
window is inactive, which the focus-state tests rely on. It needs a logged-in
window server but not Screen Recording. Mutation-check new guard logic: disable it and confirm a
test fails.
