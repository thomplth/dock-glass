import SwiftUI

/// Adjustments on top of the fitted native look, set with `.dockGlassStyle(_:)`.
///
/// Every value is relative to what was measured, so `.native` (the default) is the native
/// switcher and each knob scales one part of it. The glass itself, its tuning and its fallbacks
/// are unchanged by a style.
public struct DockGlassStyle: Sendable, Equatable {
    /// How the frosted fill follows the Liquid Glass Tint Amount slider.
    public enum Tint: Sendable, Equatable {
        /// Follow System Settings › Appearance live, as the native switcher does.
        case system
        /// A fixed tint amount from 0 (clear) to 1 (fully tinted), ignoring the system setting.
        case fixed(Double)
    }

    /// Multiplies the fitted rim opacity. 0 hides the rim.
    public var rimStrength: Double
    /// Multiplies the fitted rim width.
    public var rimWidth: Double
    /// Multiplies the fitted edge bending. 0 leaves the edges flat.
    public var edgeRefraction: Double
    /// Multiplies how strongly the selection highlight darkens (light mode) or lightens (dark
    /// mode) the glass. 0 hides it.
    public var selectionStrength: Double
    public var tint: Tint

    public init(
        rimStrength: Double = 1,
        rimWidth: Double = 1,
        edgeRefraction: Double = 1,
        selectionStrength: Double = 1,
        tint: Tint = .system
    ) {
        self.rimStrength = rimStrength
        self.rimWidth = rimWidth
        self.edgeRefraction = edgeRefraction
        self.selectionStrength = selectionStrength
        self.tint = tint
    }

    /// The native switcher as measured.
    public static let native = DockGlassStyle()

    func rim(_ fitted: GlassRim) -> GlassRim {
        GlassRim(opacity: min(1, max(0, fitted.opacity * rimStrength)), width: fitted.width * CGFloat(max(0, rimWidth)))
    }

    func tuning(_ fitted: GlassTuning) -> GlassTuning {
        var values = fitted.values
        values[.innerRefractionAmount] = values[.innerRefractionAmount].map { $0 * max(0, edgeRefraction) }
        return GlassTuning(values)
    }

    func selection(_ fitted: SelectionStyle) -> SelectionStyle {
        let strength = max(0, selectionStrength)
        switch fitted.blend {
        // Plus-darker with white is a no-op, so the effect is the distance from white.
        case .plusDarker:
            return SelectionStyle(blend: .plusDarker, gray: min(1, max(0, 1 - (1 - fitted.gray) * strength)))
        // Plus-lighter with black is a no-op, so the effect is the grey level itself.
        case .plusLighter:
            return SelectionStyle(blend: .plusLighter, gray: min(1, max(0, fitted.gray * strength)))
        }
    }

    func tintAmount(system: () -> Double) -> Double {
        switch tint {
        case .system: system()
        case .fixed(let amount): min(1, max(0, amount))
        }
    }
}

private struct DockGlassStyleKey: EnvironmentKey {
    static let defaultValue = DockGlassStyle.native
}

extension EnvironmentValues {
    public var dockGlassStyle: DockGlassStyle {
        get { self[DockGlassStyleKey.self] }
        set { self[DockGlassStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for DockGlass glass, highlights and labels inside this view.
    public func dockGlassStyle(_ style: DockGlassStyle) -> some View {
        environment(\.dockGlassStyle, style)
    }
}

extension DockGlass {
    /// The native switcher's app-name label.
    public enum Label {
        /// Measured at the standard 102pt icon size; scale it with the icon.
        public static let standardFontSize: CGFloat = 13.5
        public static let weight: Font.Weight = .bold

        /// The label colour for an appearance. Native names only the selected app; a secondary
        /// label (for other items) keeps the colour at reduced opacity.
        public static func color(for colorScheme: ColorScheme, prominent: Bool = true) -> Color {
            let base = colorScheme == .dark ? Color.white : Color.black.opacity(0.85)
            return prominent ? base : base.opacity(secondaryOpacity)
        }

        /// Not measured: native draws no unselected labels.
        public static let secondaryOpacity: Double = 0.6
    }
}

/// Styles text as the native switcher's label.
private struct DockGlassLabelModifier: ViewModifier {
    let fontSize: CGFloat
    let prominent: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.system(size: fontSize, weight: DockGlass.Label.weight))
            .foregroundStyle(DockGlass.Label.color(for: colorScheme, prominent: prominent))
    }
}

extension View {
    /// Styles text as the native switcher's app-name label. `prominent: false` is for labels the
    /// native switcher would not draw, such as unselected items.
    public func dockGlassLabel(fontSize: CGFloat = DockGlass.Label.standardFontSize, prominent: Bool = true) -> some View {
        modifier(DockGlassLabelModifier(fontSize: fontSize, prominent: prominent))
    }
}
