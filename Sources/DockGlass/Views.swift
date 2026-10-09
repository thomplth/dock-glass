import AppKit
import SwiftUI

extension View {
    /// Places Dock-style Liquid Glass behind the view, in the given shape.
    ///
    /// The glass is SwiftUI's `.clear` glass with its filter tuned to match the native Dock and
    /// Cmd-Tab switcher. It follows light and dark mode and the system's Liquid Glass tint
    /// setting, and falls back to stock `.clear` glass when tuning is unsafe or unverified (see
    /// `DockGlass.status`).
    public func dockGlass<S: InsettableShape>(in shape: S) -> some View {
        background(TunedGlass(shape: AnyShape(shape), rimShape: AnyInsettableShape(shape)))
    }

    /// Draws the native switcher's selection highlight behind an icon slot sized to the icon's
    /// artwork (`metrics.iconSize`).
    public func dockGlassSelection(_ isSelected: Bool = true, metrics: DockGlass.Metrics = .standard) -> some View {
        background {
            if isSelected { SelectionHighlight(metrics: metrics) }
        }
    }
}

struct TunedGlass: NSViewRepresentable {
    let shape: AnyShape
    let rimShape: AnyInsettableShape

    func makeNSView(context: Context) -> TunedGlassView {
        TunedGlassView(shape: shape, rimShape: rimShape)
    }

    func updateNSView(_ view: TunedGlassView, context: Context) {
        view.update(shape: shape, rimShape: rimShape)
    }
}

/// The native highlight darkens the backdrop with plus-darker blending, which also deepens its
/// saturation the way the switcher does; a translucent black fill would only grey it.
struct SelectionHighlight: View {
    let metrics: DockGlass.Metrics

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.selectionCornerRadius, style: .continuous)
            .fill(Color(white: 0.78))
            .blendMode(.plusDarker)
            .padding(-metrics.selectionPadding)
            .offset(metrics.iconCanvasOffset)
    }
}

/// The switcher's glass plate. Apple's Dock calls this shape a cartouche.
///
/// Lay out icon slots inside it at `metrics.iconSize`, spaced `metrics.iconSpacing` apart.
public struct Cartouche<Content: View>: View {
    private let metrics: DockGlass.Metrics
    private let content: Content

    public init(metrics: DockGlass.Metrics = .standard, @ViewBuilder content: () -> Content) {
        self.metrics = metrics
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.top, metrics.topPadding)
            .frame(height: metrics.plateHeight, alignment: .top)
            .dockGlass(in: RoundedRectangle(cornerRadius: metrics.plateCornerRadius, style: .continuous))
    }
}

/// An app icon in a switcher slot, drawn the way the native switcher draws it.
///
/// The full icon canvas is drawn 1:1 so the artwork lands at `metrics.iconSize` without
/// resampling; the selected icon is drawn very slightly smaller and darker, as native does.
public struct CartoucheIcon: View {
    private let image: NSImage
    private let label: String?
    private let isSelected: Bool
    private let metrics: DockGlass.Metrics

    public init(_ image: NSImage, label: String? = nil, isSelected: Bool = false, metrics: DockGlass.Metrics = .standard) {
        self.image = image
        self.label = label
        self.isSelected = isSelected
        self.metrics = metrics
    }

    public var body: some View {
        Color.clear
            .frame(width: metrics.iconSize, height: metrics.iconSize)
            .dockGlassSelection(isSelected, metrics: metrics)
            .overlay {
                Image(nsImage: image)
                    .interpolation(isSelected ? .high : .none)
                    .resizable()
                    .frame(width: metrics.iconCanvasSize, height: metrics.iconCanvasSize)
                    .brightness(isSelected ? -0.0225 : 0)
                    .scaleEffect(isSelected ? 0.985 : 1)
                    .offset(metrics.iconCanvasOffset)
            }
            .overlay(alignment: .bottom) {
                if isSelected, let label {
                    Text(label)
                        .font(.system(size: metrics.labelFontSize, weight: .bold))
                        .foregroundStyle(.primary.opacity(0.85))
                        .fixedSize()
                        .offset(y: metrics.labelOffset)
                }
            }
    }
}
