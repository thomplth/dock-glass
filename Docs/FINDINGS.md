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
variants including `_Glass.dock` and `_Glass.cartouchePopover`, reachable through
`Glass.init(explicit:)` because public `Glass` is a single-field wrapper around `_Glass`. None of
them equals the native switcher:

| Variant | Blur | Edge band height | Edge band strength |
|---|---|---|---|
| Native Cmd-Tab (fitted) | **0** | **11** | **−35** |
| `_Glass.dock` | 10 | 12.8 | −28.8 |
| `_Glass.cartouchePopover` | 10 | 5 | −60 |
| `_Glass.clear` | 10 | 20 | −60 |
| `_Glass.regular` | 5 | 20 | −60 |

The Dock variant is closest, but every variant blurs and native does not. The Dock very likely
starts from its variant and adjusts it; its binary also carries luminance-adaptation code
(`backdropLayer:didChangeLuma:`, `enableAdaptiveGlass`) that a fixed-value replica cannot follow.

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
| Plate | 176pt tall, continuous (squircle) corner radius 57.5pt, outline fit within 0.7px |
| Icons | 102pt artwork on a 134pt pitch; 37.5pt horizontal and 35pt top padding |
| Icon drawing | the full 128pt icon canvas at 1:1, offset (+0.5, +2)pt; this made unselected icons pixel-identical |
| Selection | 120×120pt square, 9pt around the artwork, continuous corner radius 33pt (concentric with the icon), box matches to the pixel |
| Selected icon | drawn at 98.5% and 2% darker |
| Label | 13.5pt bold, 31pt below the icon slot |

## Material

Fitted by coordinate descent over the glass inputs, rendering the real component over two
backdrops (saturated stripes under text, and a dark-to-light ramp with discs and a grid).

| Input | Stock `.clear` | Light | Dark |
|---|---|---|---|
| `inputBlurRadius` | 10 | 0 | 0 |
| `inputInnerRefractionHeight` | 20 | 11 | 11 |
| `inputInnerRefractionAmount` | −60 | −35 | −35 |
| `inputFaceColorMatrixBlack` | 0.2 / 0.05 | 0.056 | 0.06 |
| `inputFaceColorMatrixWhite` | 0.95 / 0.8 | 0.89 | 0.74 |
| `inputFaceColorMatrixSaturation` | 1 | 1.39 | 1.19 |
| `inputFaceColorMatrixMaxLumaSDR` | 1 | 1 | 0.95 |
| Rim (white, plus-lighter) | none | 0.275 opacity, 0.875pt | 0.175 opacity, 0.875pt |
| Selection | | grey 0.78, plus-darker | grey 0.25, plus-lighter |
| **Error** | 13.7 | **2.95** | **4.01** |

The plus-darker selection darkens and saturates the backdrop the way native does; a translucent
black fill only greys it. The built-in ring-shadow inputs and `inputRefractionDistance*` made
matters worse and are left alone.

## The tint slider

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
- Unknown input keys, and even a missing filter, are silent no-ops. A macOS update that renames an
  input would degrade silently, so DockGlass checks every input it needs before tuning.

## What still differs

- A thin ring along the outline: native's rim is softer and shifts colour with the backdrop.
- A faint colour cast in dark mode.
- Live Dock content: the Calendar icon showing today's date and app badges.
- Backdrops unlike the two fitted ones may drift, since native adapts to backdrop luminance.
