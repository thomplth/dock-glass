# DockGlass

SwiftUI glass and switcher chrome that match the macOS Dock and Cmd-Tab switcher on macOS 26 and
27, fitted pixel by pixel against each version's native switcher.

SwiftUI's public Liquid Glass offers `.regular` and `.clear`. Neither looks like the Dock or the
app switcher: the native switcher does not blur at all, and bends only a thin band along its
edges. DockGlass renders SwiftUI's own `.clear` glass and tunes the system glass filter behind it
to measured values, so it keeps Apple's renderer and follows the system's settings.

![A DockGlass cartouche with stock apps, and a shadowed DockGlass plate](media/demo-light.png)

This is not a dock widget. It reproduces the *material and geometry* of Apple's switcher plate,
which the Dock's own code calls a cartouche.

## Installation

Requires macOS 26 or later and Swift 6.2. Add DockGlass with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/thomplth/dock-glass.git", from: "0.1.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "DockGlass", package: "dock-glass"),
    ]),
]
```

In Xcode, use File › Add Package Dependencies and enter the repository URL.

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

## macOS 26

macOS 26's switcher has the same geometry as 27's but a different material: it blurs slightly and
bends a wider band. DockGlass carries a separate look fitted against it. Native on top, DockGlass
below, over the two fitting backdrops:

![macOS 26 light mode: native switcher above, DockGlass below](media/macos26-light.png)

![macOS 26 dark mode: native switcher above, DockGlass below](media/macos26-dark.png)

## System settings

| Setting | Behaviour |
|---|---|
| Light and dark mode | Separate fitted tables; the selection highlight darkens in light mode and lightens in dark mode, as native does. |
| Liquid Glass Tint Amount (System Settings › Appearance) | Frosts continuously along the slider, as the native switcher does, and updates live when the slider moves. SwiftUI's own clear glass only frosts at full tint. |
| Reduce Transparency, Increase Contrast | DockGlass steps aside and shows the system's own glass. |

`DockGlass.status` reports whether tuned glass is showing, or why stock glass is showing instead.

## Caveats

DockGlass writes to an undocumented Core Animation filter (`glassBackground`) through key-value
coding. That is not public API:

- **Not for the App Store.** App Review rejects non-public API use.
- **macOS updates can change it.** Unknown keys fail silently, so DockGlass checks every input
  it needs before tuning and falls back to stock `.clear` glass when one is missing. Each macOS
  version has its own fitted look (currently 26 and 27), because each version's switcher looks
  different; an unlisted version shows stock `.clear` glass.
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
`swift run dockglass-demo` shows the component on its own.

## License

MIT
