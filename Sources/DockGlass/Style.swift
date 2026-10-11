import AppKit
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
    /// Which window state the glass draws in. `.native` (the default) is the state the look was
    /// fitted in, whatever the host window's state.
    public var focusState: FocusState

    public init(
        rimStrength: Double = 1,
        rimWidth: Double = 1,
        edgeRefraction: Double = 1,
        selectionStrength: Double = 1,
        tint: Tint = .system,
        focusState: FocusState = .native
    ) {
        self.rimStrength = rimStrength
        self.rimWidth = rimWidth
        self.edgeRefraction = edgeRefraction
        self.selectionStrength = selectionStrength
        self.tint = tint
        self.focusState = focusState
    }

    /// The native switcher as measured.
    public static let native = DockGlassStyle()

    func rim(_ fitted: GlassRim) -> GlassRim {
        GlassRim(opacity: min(1, max(0, fitted.opacity * rimStrength)), width: fitted.width * CGFloat(max(0, rimWidth)))
    }

    func tuning(_ fitted: GlassTuning) -> GlassTuning {
        var tuning = fitted
        tuning.values[.innerRefractionAmount] = tuning.values[.innerRefractionAmount].map { $0 * max(0, edgeRefraction) }
        return tuning
    }

    /// The system rim scaled like the stroke. Up to 1, `rimStrength` fades the lights' colour, as
    /// the system does to hide the rim; above 1 it brightens them. `rimWidth` scales how far each
    /// light reaches in from the outline.
    func highlight(_ fitted: GlassHighlight) -> GlassHighlight {
        guard rimStrength != 1 || rimWidth != 1 else { return fitted }
        var values = fitted.values
        func scale(_ property: GlassHighlight.Property, by factor: Double, floor: Double = 0) {
            let base = values[property] ?? GlassHighlight.systemValues[property]!
            values[property] = base * max(floor, factor)
        }
        let strength = max(0, rimStrength)
        scale(.keyOpacity, by: min(1, strength))
        scale(.fillOpacity, by: min(1, strength))
        scale(.keyAmount, by: max(1, strength))
        scale(.fillAmount, by: max(1, strength))
        // A height of 0 draws a solid band, like an amount of 0.
        scale(.keyHeight, by: rimWidth, floor: 0.05)
        scale(.fillHeight, by: rimWidth, floor: 0.05)
        return GlassHighlight(values)
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
        /// Measured at the standard 102pt icon size; scale it with the icon. Fitted on macOS
        /// 27.0.1 by rendering the system font over native label ink, on a clean light capture
        /// and a dark one, which both chose the same size and weight (see Docs/FINDINGS.md).
        public static let standardFontSize: CGFloat = 12.8125
        /// The system font's continuous weight axis value: just under bold (700), heavier than
        /// semibold (590). Named weights cannot reach it, so use `font(size:)`.
        public static let weightAxisValue: CGFloat = 680
        /// The nearest named weight, for text that cannot take `font(size:)`.
        public static let weight: Font.Weight = .bold

        /// The label font at a size, on the fitted weight axis value.
        @MainActor
        public static func font(size: CGFloat) -> Font {
            if let cached = fonts[size] { return cached }
            let font = Font(nsFont(size: size) as CTFont)
            fonts[size] = font
            return font
        }

        /// The AppKit label font at a size, for drawing outside SwiftUI.
        public static func nsFont(size: CGFloat) -> NSFont {
            let base = NSFont.systemFont(ofSize: size, weight: .bold)
            let descriptor = base.fontDescriptor.addingAttributes([
                NSFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): [
                    weightAxisTag: weightAxisValue,
                ],
            ])
            return NSFont(descriptor: descriptor, size: size) ?? base
        }

        /// 'wght'
        static let weightAxisTag = 0x7767_6874
        @MainActor private static var fonts: [CGFloat: Font] = [:]

        /// The label colour for an appearance. Native names only the selected app; a secondary
        /// label (for other items) keeps the colour at reduced opacity.
        public static func color(for colorScheme: ColorScheme, prominent: Bool = true) -> Color {
            // Fitted with the font: black at 80% in light mode, white at 95% in dark mode.
            let base = colorScheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.8)
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
            .font(DockGlass.Label.font(size: fontSize))
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
