# Findings: matching the macOS 27 Dock switcher

Everything here was measured on macOS 27.0.1 (26A434) on a 2560×1440 display at 2× scale. Error
figures are mean absolute differences per colour channel, out of 255, between a native capture and
the DockGlass replica over the same backdrop.

## What the native switcher is

Apple's Dock draws the Cmd-Tab switcher itself. Its own code calls the switcher
`ApplicationSwitcher` / `AppSwitcher`, the glass material `DockGlassMaterial`
(`DockGlassMaterialLayerController`, `DockGlassMaterialEnvironment`), and the rounded plate a
**cartouche** (`ECCartoucheGlassLayerController`, `CartoucheMaterialLayerController`). A material
variant is chosen per background style through `_glassMaterialVariantForBackgroundStyle:`.

SwiftUI exposes only `Glass.regular`, `.clear` and `.identity` publicly. Privately it has named
variants including `_Glass.dock` and `_Glass.cartouchePopover`, reachable because public `Glass`
is a single-field wrapper around `_Glass`. Read at 160pt tall, in the inactive state every earlier
comparison was made in, and in the active state the native switcher draws in:

| Variant | Blur (inactive / active) | Edge band height | Edge band strength |
|---|---|---|---|
| Native Cmd-Tab (fitted, active, 176pt) | – / **0** | **13.22** | **−29.95** |
| `_Glass.dock` | 10 / 0 | 12.8 | −28.8 |
| `_Glass.cartouchePopover` | 10 / 5 | 5 | −60 |
| `_Glass.clear` | 10 / 0 | 20 | −60 |
| `_Glass.regular` | 5 / – | 20 | −60 |

Measured inactive, every variant blurred and none matched; that comparison was the wrong state.
Drawn active, the Dock variant is the native material (see the focus state, below). The Dock's
binary also carries luminance-adaptation code (`backdropLayer:didChangeLuma:`,
`enableAdaptiveGlass`); nothing in the captures needed it.

## How the glass renders

SwiftUI glass draws through a `CABackdropLayer` carrying a private `glassBackground` filter. The
filter's inputs (`inputBlurRadius`, `inputInnerRefractionHeight`, `inputFaceColorMatrix*` and
around 70 more) are readable and writable through key-value coding at
`filters.glassBackground.<input>`. Two details matter:

- The backdrop is sampled at half resolution (`scale` 0.5); native matches that.
- The "glass" look of the native switcher is a thin refraction band along the inside of the
  outline. Stock `.clear` glass has a wider band and a 10pt blur that smears it away.

## Geometry

Measured by diffing each capture against a capture of the backdrop alone, tracing the outline row
by row, and fitting SwiftUI shape paths to it.

| | Value |
|---|---|
| Plate | 176pt tall, continuous (squircle) corner radius 58pt; a 17-icon plate is 2320pt wide, centred on whole points |
| Icons | 102pt artwork on a 134pt pitch; 37pt horizontal and 35pt top padding |
| Icon drawing | the full 128pt icon canvas at 1:1, offset (0, +2)pt; unselected icons are pixel-identical |
| Selection | 120×120pt square, 9pt around the artwork, continuous corner radius 33pt (concentric with the icon), box matches to the pixel |
| Selected icon | drawn at 98.5% and 2% darker |
| Label | 12.8125pt at SF weight 680; black at 80% (light), white at 95% (dark); 31pt below the icon slot, 0.25pt left of centre |

## The focus state (fitted 2026-10-12, macOS 27.0.1)

SwiftUI draws Liquid Glass differently in an inactive window, and the window that matters is the
one hosting the glass. A non-activating panel in an app that never activates (the fitting tool's,
or a switcher overlay's) always draws inactive. Every fit before this one was measured that way,
against a native switcher that draws **active**: the Dock's switcher is never in an inactive
window. The tuning had been compensating for the wrong state.

What the inactive state changes, read off the layers of the same glass in both states:

| | Inactive | Active |
|---|---|---|
| Specular rim (`CASDFLayer` with a `CASDFKeyFillHighlightEffect`) | layer opacity 0, key and fill colours at alpha 0 | shown |
| `inputBlurRadius` (clear) | 10 | 0 |
| `inputBlurOpacity0…3`, `inputBlurDistance0/1` | blur everywhere | blur bands off |
| `inputOuterRefraction*` (clear) | 0 | 32 / 20 |
| `inputFaceColorMatrix*` (clear) | frosted (white fill at 0.1) | clear |

The old white `plusLighter` stroke stood in for the hidden specular rim, which is why a thin ring
along the outline never matched.

**The lever.** The window's private `_hasActiveAppearanceIgnoringKeyFocus` decides; SwiftUI copies
it into the internal `EnvironmentValues.windowAppearsActive` when it builds a hosting view's
environment. Setting that value on DockGlass's own subtree draws its glass in either state and
leaves the host window and its other glass alone. The public `appearsActive`,
`controlActiveState` and `materialActiveAppearance`, and overriding the private method on a
view rather than the window, have no effect on glass. The setter is called through a small C
shim, because a Swift mutating accessor takes `self` in the `swiftself` register; DockGlass looks
it up at run time and checks it round-trips a value before using it.

## Material (macOS 27)

Drawn active, SwiftUI's private Dock glass (`_Glass.dock`) **is** the native switcher's
material. Untuned it already scored 0.5 and 0.16 over the glass, against 2.0 for the old tuned
`.clear`. Its edge band scales with the glass's height (0.08 × height in, −0.18 × height of
bending); the native switcher's is slightly shallower and gentler, and that is the only input
DockGlass overrides:

| Input | `_Glass.dock` at 176pt | Native |
|---|---|---|
| `inputInnerRefractionHeight` | 14.08 | **13.22** (0.0751 × height) |
| `inputInnerRefractionAmount` | −31.68 | **−29.95** (−0.1702 × height) |

Fitted in dark mode, then confirmed by an independent light-mode capture, which chose the same
values. Every other input, the rim included, is the Dock glass's own: fitting the highlight's
twelve properties and the filter's highlight inputs found nothing better than the system's values.

Errors over the whole plate with live Dock content excluded (Calendar's date, badges), out of 255:

| Capture | Glass | Rim band (4pt) | Rim corners | Plate |
|---|---|---|---|---|
| Dark, backdrop A / B | 0.018 / 0.007 | 0.014 / 0.106 | 0.059 / 0.105 | 0.33 / 0.34 |
| Light, backdrop A / B | 0.016 / 0.008 | 0.013 / 0.099 | 0.061 / 0.125 | 0.32 / 0.31 |

For comparison, the previous look (inactive `.clear`, tuned, white stroke) scored 2.2 / 1.8 over
the glass and 4.3 / 5.4 over the rim on the same captures.

Three measurement errors had hidden this:

- **The fitting panel clipped the glass.** The glass draws a one-pixel outline just outside its
  shape; a panel cut to the plate clipped it on one side. The panel now has a margin.
- **Plate width.** The plate is 2320pt for 17 icons (37pt padding), not 2321pt; at 37.5pt the
  plate sat half a point off and the icon offset of +0.5pt had absorbed it.
- **Corner radius.** With placement right, the corners fit at 58pt (0.06 against 2.25 at 57.5pt).

The selection highlight still uses plus-darker grey 0.78 (light) and plus-lighter grey 0.25
(dark); refitting on the new glass left both unchanged.

### macOS 26 (history)

macOS 26's look was first fitted the old way, on `.clear` glass in an inactive panel. Refitted in
the active state on 2026-10-12, it matches 26's switcher at least as well, so 26's switcher draws
active too and both versions now do. Plate error, backdrops A / B:

| macOS 26.6.1 | Inactive fit | Active fit |
|---|---|---|
| Light | 2.90 / 2.43 | 2.66 / 2.37 |
| Dark | 2.45 / 2.60 | 2.45 / 2.02 |

The old look forced active scored 8.9 / 9.9 (light) and 6.1 / 6.3 (dark), so a fit only holds in
the state it was made in. Untuned and active, `.clear` (10.4 / 7.8 light) comes closer than the
Dock glass (11.3 / 10.7), so 26 keeps `.clear` as its base. With the active state, the fitted white
stroke went to 0: 26 uses the system's own rim, as 27 does.

Left free, the fit also moved the selected icon to full size and brightness (plate 1.51 / 1.24 in
light). Those values are shared with 27, which fits 0.985 and −0.0225, so the 26 fit froze them;
a per-version selected icon would close that gap.

## The tint slider

**macOS 27 (2026-10-12).** The native switcher follows the slider the way the Dock glass does,
with a steeper blur: blur rises as 7 × tint to 3.5 at tint 0.5, then the frosted fill opacity
rises as 2 × tint − 1 with a fill blur of 8. The blur bands (`inputBlurOpacity0…3` 1, 0.5, 0.5, 1)
switch on with any tint. SwiftUI's own Dock glass reaches only 1.5 blur. Glass error per capture
(dark, backdrops A / B): tint 0.25 0.06 / 0.09, 0.5 0.06 / 0.08, 0.75 0.04 / 0.05,
1 0.002 / 0.002. Light mode was checked at tint 0 only. The section below is the clear-based fill
curve that macOS 26's look still uses.

System Settings › Appearance has a continuous **Liquid Glass Tint Amount** slider, stored as the
global default `NSGlassTintAmount`. SkyLight broadcasts changes as
`kSLSCoordinatedGlassAppearanceSettingsChangeNotificationName`, and a running process sees the
defaults change through key-value observing.

The slider drives the glass filter's frosted fill (`inputBlurFill*`, and the face fill colour on
regular glass), not the inputs DockGlass fits. On clear glass SwiftUI only switches the fill on at
full tint, while the native switcher frosts continuously. DockGlass therefore drives the fill on a
curve through the system's own values at 0 and 1 and fitted values halfway:

| Tint | Fill opacity | Fill blur | Error |
|---|---|---|---|
| 0 | 0 | 0 | 2.95 |
| 0.5 | 0.7 | 2 | 4.47 (6.04 with SwiftUI's stepwise response) |
| 1 | 1 | 8 | 3.78, with no tint-specific fitting |

Dark mode is assumed to follow the slider the same way; only light mode was fitted at 0.5.

## Keeping the values in place

Verified off-screen, by reading filter values back after each event:

- Content, size and corner changes, hiding and reshowing, and detaching and reattaching the
  hosting view keep the written values.
- An appearance change makes SwiftUI rewrite the inputs to stock on the same layer.
- Rebuilding the glass replaces the backdrop layer.
- Key-value observing `filters` on the backdrop layer fires on that rewrite, and writing back
  inside the callback holds the values. The handler must write only changed values and must not
  re-enter: writing an input re-posts `filters`, and an unguarded handler recursed until it
  crashed.
- The specular rim's effect (`CASDFKeyFillHighlightEffect`) never renders a change made to the
  layer's current effect in place. DockGlass assigns a modified copy, and observes `effect`,
  which SwiftUI replaces whenever it re-resolves the glass.
- Unknown input keys, and even a missing filter, are silent no-ops. A macOS update that renames an
  input would degrade silently, so DockGlass checks every input it needs before tuning.

## macOS 26

Measured in a macOS 26.6.1 (25G76) virtual machine with a 1024×768 screen at 2× scale.

**Geometry is the same as 27.** With few enough apps for the switcher to fit the screen, the plate
is 176pt tall with the same continuous corner (profile within a pixel of 27's at every row) and
102pt icons on a 134pt pitch. With more apps than fit, the Dock shrinks the whole switcher to the
screen width; that is screen fitting, not a version difference.

**The material differs.** 26's switcher blurs slightly and bends a wider, stronger band than 27's,
and casts a faint shadow outside the plate that 27's does not. Fitted against 26's own switcher
on `.clear` glass drawn active (the first, inactive fit in brackets):

| Input | Light | Dark |
|---|---|---|
| `inputBlurRadius` | 3.125 (2) | 3 (2) |
| `inputInnerRefractionHeight` | 24 (22) | 24 (23) |
| `inputInnerRefractionAmount` | −56.25 (−55) | −55 (−55) |
| `inputFaceColorMatrixBlack` | 0.2135 (0.116) | 0.09 (0.03) |
| `inputFaceColorMatrixWhite` | 0.9425 (0.92) | 0.785 (0.77) |
| `inputFaceColorMatrixSaturation` | 0.95 (1.03) | 0.95 (0.95) |
| Rim | the system's (0.175 stroke) | the system's (0.075 stroke) |

| Glass on 26 | Light error | Dark error |
|---|---|---|
| Stock `.clear` | 11.09 | 9.72 |
| 27's look | 14.34 | 11.73 |
| **26's look** | **2.89** | **2.70** |
| 26's look, after the geometry fixes (2026-10-12) | 2.67 | 2.52 |
| **26's look, refitted active (2026-10-12)** | **2.51** | **2.24** |

27's look is worse than stock on 26, which is why each version gets its own look. The last row
is the same look re-measured with 27's padding, corner and panel-margin fixes in place; the other
rows date from the original fit.

**The rim effect is older too.** macOS 26's `CASDFKeyFillHighlightEffect` lacks the three
`diffuse*` properties. Key-value coding throws on a key an object lacks, and Swift cannot catch
it, so every read and write of the effect checks `responds(to:)` first. Without that check, any
DockGlass view crashed on 26.

**The filter is older:** 55 inputs instead of 77. The six core inputs exist with the same stock
values as on 27; `inputFaceColorMatrixMaxLuma`, `inputFaceColorMatrixMaxLumaSDR` and the two
`inputBlurFill*` inputs do not. DockGlass treats the core six as required and the rest as optional,
skipping them where the filter lacks them, so 26 has no tint response to drive.

`glass-fit inspect` prints the filter inputs and stock values on any system; run it first on a new
macOS version.

## What still differs

- The selected icon: native resamples it differently; the artwork differs by about 8/255 inside
  its own box, with the highlight band around it at about 6.
- Live Dock content: the Calendar icon showing today's date and app badges.
- Backdrops unlike the two fitted ones may drift if native adapts to backdrop luminance; nothing
  in these captures showed it.
- Plate heights other than 176pt follow the Dock glass's own proportional scaling; only 176pt was
  measured.
- macOS 26's faint shadow outside the plate is not drawn.

## Label font (fitted 2026-10-10, macOS 27.0.1)

The label was first set by eye to 13.5pt bold, which reads heavier and slightly larger than
native. It was refitted by isolating native label ink and rendering candidates over it:

- **Clean light capture.** The native switcher over a uniform grey backdrop, label "Orca". Ink
  is the drop in red below the plate's own level.
- **Dark capture.** The two-backdrop dark capture, white label over yellow. Ink is the rise in
  blue above the local background.
- **Search.** System font weights 0.25–0.45, sizes 12.75–13.5pt in eighth-points, text opacity
  0.6–1, whole-pixel alignment plus a quarter-point shift. The score is the mean absolute
  difference of ink.

With named weights only, both captures put semibold 13.375pt first and bold 12.875pt
second, but semibold's stems never reach full coverage the way native's do. On the system font's
continuous weight axis (560–720), both captures choose **weight 680 at 12.8125pt** (light 85.7,
dark 103.6, against 105.9–115.5 for the old 13.5pt bold). Opacity: 0.80 in light mode and 0.95 in
dark mode. The old label was mostly too large, not too heavy.
