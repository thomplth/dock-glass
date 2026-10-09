# DockGlass

SwiftUI glass and switcher chrome that match the macOS 27 Dock and Cmd-Tab switcher, fitted
pixel by pixel against the native switcher.

SwiftUI's public Liquid Glass offers `.regular` and `.clear`. Neither looks like the Dock or the
app switcher: the native switcher does not blur at all, and bends only a thin band along its
edges. DockGlass renders SwiftUI's own `.clear` glass and tunes the system glass filter behind it
to measured values, so it keeps Apple's renderer and follows the system's settings.

This is not a dock widget. It reproduces the *material and geometry* of Apple's switcher plate,
which the Dock's own code calls a cartouche.

## Usage

```swift
import DockGlass

Cartouche {
    HStack(alignment: .top, spacing: DockGlass.Metrics.standard.iconSpacing) {
        ForEach(apps) { app in
            CartoucheIcon(app.icon, label: app.name, isSelected: app == selected)
        }
    }
}
```

Or put the glass behind any view:

```swift
content.dockGlass(in: RoundedRectangle(cornerRadius: 57.5, style: .continuous))
icon.dockGlassSelection(isSelected)
```

`DockGlass.Metrics` carries the native geometry (176pt plate, 57.5pt continuous corner, 102pt
icons on a 134pt pitch, a 120pt selection square with a concentric 33pt corner) and scales it to
other icon sizes.

## System settings

| Setting | Behaviour |
|---|---|
| Light and dark mode | Separate fitted tables; the selection highlight darkens in light mode and lightens in dark mode, as native does. |
| Liquid Glass Tint Amount (System Settings › Appearance) | DockGlass overrides only the inputs it fitted. The frosted fill the tint slider drives stays under the system's control, so the user's choice still applies. |
| Reduce Transparency, Increase Contrast | DockGlass steps aside and shows the system's own glass. |

`DockGlass.status` reports whether tuned glass is showing, or why stock glass is showing instead.

## Caveats

DockGlass writes to an undocumented Core Animation filter (`glassBackground`) through key-value
coding. That is not public API:

- **Not for the App Store.** App Review rejects non-public API use.
- **macOS updates can change it.** Unknown keys fail silently, so DockGlass checks every input
  it needs before tuning and falls back to stock `.clear` glass when one is missing. Tuning is
  only applied on macOS versions the tables were fitted on (currently 27).
- **The values are fitted, not designed.** They match the native switcher closely on the
  backdrops they were fitted over; see [Docs/FINDINGS.md](Docs/FINDINGS.md) for the method and the
  remaining differences.

## Refitting

`glass-fit` captures the native switcher over two test backdrops and searches for the tuning
that matches it best, rendering the real `Cartouche` while it searches:

```sh
swift run glass-fit capture captures/light
swift run glass-fit fit captures/light --apps self,<bundle id>,...
```

Both commands take over the screen while they run. Quit any app that replaces Cmd-Tab first.

## License

MIT
