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

    /// Draws the native selection highlight behind the view, filling its bounds in `shape`.
    ///
    /// Size and pad the view to the highlight you want; for content other than an app icon, the
    /// native look is `DockGlass.Metrics.selectionPadding` around it with a corner radius of the
    /// content's own radius plus that padding. The highlight blends with the glass behind it, so
    /// it must not sit inside a compositing group (a shadow, `drawingGroup` or
    /// `compositingGroup`) between it and the glass.
    public func dockGlassSelection<S: Shape>(_ isSelected: Bool = true, in shape: S) -> some View {
        background {
            if isSelected { DockGlassSelectionHighlight(shape) }
        }
    }
}

struct TunedGlass: NSViewRepresentable {
    let shape: AnyShape
    let rimShape: AnyInsettableShape

    func makeNSView(context: Context) -> TunedGlassView {
        TunedGlassView(shape: shape, rimShape: rimShape, style: context.environment.dockGlassStyle)
    }

    func updateNSView(_ view: TunedGlassView, context: Context) {
        view.update(shape: shape, rimShape: rimShape, style: context.environment.dockGlassStyle)
    }
}

/// The native selection highlight in any shape, filling the space it is offered.
///
/// In light mode the native highlight darkens the backdrop with plus-darker blending, which also
/// deepens its saturation the way the switcher does; a translucent black fill would only grey it.
/// In dark mode it lightens instead.
public struct DockGlassSelectionHighlight<S: Shape>: View {
    private let shape: S
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dockGlassStyle) private var style

    public init(_ shape: S) {
        self.shape = shape
    }

    public var body: some View {
        let fitted = colorScheme == .dark ? DockGlass.selection.dark : DockGlass.selection.light
        let selection = style.selection(fitted)
        shape
            .fill(Color(white: selection.gray))
            .blendMode(selection.blend == .plusDarker ? .plusDarker : .plusLighter)
    }
}

/// The highlight around an icon slot, concentric with the icon's corners.
struct SelectionHighlight: View {
    let metrics: DockGlass.Metrics

    var body: some View {
        DockGlassSelectionHighlight(RoundedRectangle(cornerRadius: metrics.selectionCornerRadius, style: .continuous))
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
            .dockGlass(in: metrics.plateShape)
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
                    .brightness(isSelected ? DockGlass.SelectedIcon.brightness : 0)
                    .scaleEffect(isSelected ? DockGlass.SelectedIcon.scale : 1)
                    .offset(metrics.iconCanvasOffset)
            }
            .overlay(alignment: .bottom) {
                if isSelected, let label {
                    Text(label)
                        .dockGlassLabel(fontSize: metrics.labelFontSize)
                        .fixedSize()
                        .offset(x: DockGlass.SelectedIcon.labelShift.width * metrics.scale,
                                y: metrics.labelOffset + DockGlass.SelectedIcon.labelShift.height * metrics.scale)
                }
            }
    }
}

extension DockGlass {
    /// How native draws the selected icon and its label, at the standard icon size.
    enum SelectedIcon {
        nonisolated(unsafe) static var scale = 0.985
        nonisolated(unsafe) static var brightness = -0.0225
        /// Nudges the label from centred under the slot at `Metrics.labelOffset`.
        nonisolated(unsafe) static var labelShift = CGSize(width: -0.25, height: 0)
    }
}
