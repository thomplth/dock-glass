import Foundation

/// Values DockGlass writes onto the system glass filter so `.clear` glass renders like the
/// macOS Dock and Cmd-Tab switcher.
///
/// DockGlass owns only these inputs. Everything else on the filter stays under the system's
/// control, including the frosted fill that the Liquid Glass tint setting
/// (System Settings › Appearance) drives, so the user's choice still applies on top.
public struct GlassTuning: Sendable, Equatable {
    /// Inputs of the private `glassBackground` filter that DockGlass overrides.
    public enum Input: String, CaseIterable, Sendable {
        case blurRadius = "inputBlurRadius"
        case innerRefractionHeight = "inputInnerRefractionHeight"
        case innerRefractionAmount = "inputInnerRefractionAmount"
        case faceColorBlack = "inputFaceColorMatrixBlack"
        case faceColorWhite = "inputFaceColorMatrixWhite"
        case faceColorSaturation = "inputFaceColorMatrixSaturation"
    }

    public var values: [Input: Double]

    public init(_ values: [Input: Double]) {
        self.values = values
    }

    /// Fitted against the native macOS 27 Cmd-Tab switcher in light mode at tint 0, scored over
    /// two backdrops (mean absolute error 2.98/255 across the whole plate).
    public static let light = GlassTuning([
        .blurRadius: 0,
        .innerRefractionHeight: 11,
        .innerRefractionAmount: -35,
        .faceColorBlack: 0.056,
        .faceColorWhite: 0.89,
        .faceColorSaturation: 1.39,
    ])

    /// Dark mode has not been fitted yet; until it is, dark appearances render stock glass.
    public static let dark: GlassTuning? = nil
}

/// The hairline rim the native plate draws along its outline, which no glass input reproduces.
public struct GlassRim: Sendable, Equatable {
    public var opacity: Double
    public var width: CGFloat

    public init(opacity: Double, width: CGFloat) {
        self.opacity = opacity
        self.width = width
    }

    public static let light = GlassRim(opacity: 0.275, width: 0.875)
}
