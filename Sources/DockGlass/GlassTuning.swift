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
        /// Brightness ceiling of the face colour matrix, on HDR and on SDR displays. The tint
        /// setting drives these on regular glass but not on clear glass, which DockGlass uses.
        case faceColorMaxLuma = "inputFaceColorMatrixMaxLuma"
        case faceColorMaxLumaSDR = "inputFaceColorMatrixMaxLumaSDR"

        /// Inputs every supported filter has. A missing one means the filter changed, so DockGlass
        /// falls back to stock glass rather than apply half a tuning.
        public static let core: [Input] = [
            .blurRadius, .innerRefractionHeight, .innerRefractionAmount,
            .faceColorBlack, .faceColorWhite, .faceColorSaturation,
        ]

        /// Inputs only newer filters have (macOS 27); applied where present, skipped elsewhere.
        public var isOptional: Bool { !Self.core.contains(self) }
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
        .faceColorMaxLuma: 1,
        .faceColorMaxLumaSDR: 1,
    ])

    /// Fitted against the native macOS 27 Cmd-Tab switcher in dark mode at tint 0, scored over
    /// two backdrops (mean absolute error 4.01/255 across the whole plate).
    public static let dark: GlassTuning? = GlassTuning([
        .blurRadius: 0,
        .innerRefractionHeight: 11,
        .innerRefractionAmount: -35,
        .faceColorBlack: 0.06,
        .faceColorWhite: 0.74,
        .faceColorSaturation: 1.19,
        .faceColorMaxLuma: 1,
        .faceColorMaxLumaSDR: 0.95,
    ])
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
    public static let dark = GlassRim(opacity: 0.175, width: 0.875)
}

/// How the selection highlight tints the backdrop behind a selected icon.
public struct SelectionStyle: Sendable, Equatable {
    public enum Blend: Sendable, Equatable {
        /// Light mode: darkens and deepens saturation.
        case plusDarker
        /// Dark mode: lightens.
        case plusLighter
    }

    public var blend: Blend
    /// Grey level blended over the backdrop.
    public var gray: Double

    public init(blend: Blend, gray: Double) {
        self.blend = blend
        self.gray = gray
    }

    public static let light = SelectionStyle(blend: .plusDarker, gray: 0.78)
    public static let dark = SelectionStyle(blend: .plusLighter, gray: 0.25)
}

/// How the frosted fill follows the Liquid Glass Tint Amount slider (System Settings ›
/// Appearance).
///
/// The native switcher frosts continuously along the slider, but SwiftUI's clear glass only
/// switches its fill on at full tint. DockGlass therefore drives the two fill inputs itself, on a
/// curve that passes through the system's own values at 0 (no fill) and 1 (full fill), and through
/// a value fitted against the native switcher halfway.
public struct TintResponse: Sendable, Equatable {
    /// Fill opacity at tint 0.5. Tint 0 and 1 map to 0 and 1, as the system does.
    public var halfwayFillOpacity: Double
    /// Fill blur radius at tint 0.5. Tint 0 and 1 map to 0 and the system's 8.
    public var halfwayFillBlurRadius: Double

    public init(halfwayFillOpacity: Double, halfwayFillBlurRadius: Double) {
        self.halfwayFillOpacity = halfwayFillOpacity
        self.halfwayFillBlurRadius = halfwayFillBlurRadius
    }

    static let fillOpacityKey = "inputBlurFillNormalOpacity"
    static let fillBlurRadiusKey = "inputBlurFillBlurRadius"
    static let fullFillBlurRadius = 8.0

    /// Filter values for a tint amount in 0...1: piecewise linear through 0, 0.5 and 1.
    func values(tint: Double) -> [String: Double] {
        let t = min(1, max(0, tint))
        func curve(_ halfway: Double, _ full: Double) -> Double {
            t <= 0.5 ? t / 0.5 * halfway : halfway + (t - 0.5) / 0.5 * (full - halfway)
        }
        return [
            Self.fillOpacityKey: curve(halfwayFillOpacity, 1),
            Self.fillBlurRadiusKey: curve(halfwayFillBlurRadius, Self.fullFillBlurRadius),
        ]
    }

    /// Fitted against the native switcher at tint 0.5 in light mode (mean absolute error
    /// 4.47/255, against 6.04 for SwiftUI's own stepwise response).
    public static let light = TintResponse(halfwayFillOpacity: 0.7, halfwayFillBlurRadius: 2)
    /// Not fitted separately yet; assumes dark mode follows the slider the way light mode does.
    public static let dark = TintResponse(halfwayFillOpacity: 0.7, halfwayFillBlurRadius: 2)
}

/// Everything DockGlass draws differently per macOS version.
public struct GlassLook: Sendable, Equatable {
    public var light: GlassTuning?
    public var dark: GlassTuning?
    public var lightRim: GlassRim
    public var darkRim: GlassRim
    public var lightSelection: SelectionStyle
    public var darkSelection: SelectionStyle
    public var lightTint: TintResponse
    public var darkTint: TintResponse

    public init(
        light: GlassTuning?, dark: GlassTuning?,
        lightRim: GlassRim, darkRim: GlassRim,
        lightSelection: SelectionStyle, darkSelection: SelectionStyle,
        lightTint: TintResponse, darkTint: TintResponse
    ) {
        self.light = light
        self.dark = dark
        self.lightRim = lightRim
        self.darkRim = darkRim
        self.lightSelection = lightSelection
        self.darkSelection = darkSelection
        self.lightTint = lightTint
        self.darkTint = darkTint
    }

    /// Fitted on macOS 26.6.1 (25G76) against its own switcher, which blurs slightly and bends a
    /// wider band than 27's. Its filter lacks the brightness-ceiling and tint-fill inputs, so the
    /// tint response has nothing to drive there. Mean absolute error: light 2.89/255 (stock clear
    /// 11.09, 27's look 14.34); dark 2.70/255 (stock 9.72, 27's look 11.73).
    public static let macOS26 = GlassLook(
        light: GlassTuning([
            .blurRadius: 2,
            .innerRefractionHeight: 22,
            .innerRefractionAmount: -55,
            .faceColorBlack: 0.116,
            .faceColorWhite: 0.92,
            .faceColorSaturation: 1.03,
            .faceColorMaxLuma: 1,
            .faceColorMaxLumaSDR: 1,
        ]),
        dark: GlassTuning([
            .blurRadius: 2,
            .innerRefractionHeight: 23,
            .innerRefractionAmount: -55,
            .faceColorBlack: 0.03,
            .faceColorWhite: 0.77,
            .faceColorSaturation: 0.95,
            .faceColorMaxLuma: 1,
            .faceColorMaxLumaSDR: 1,
        ]),
        lightRim: GlassRim(opacity: 0.175, width: 0.875),
        darkRim: GlassRim(opacity: 0.075, width: 0.875),
        lightSelection: .light, darkSelection: .dark,
        lightTint: .light, darkTint: .dark
    )

    /// Fitted on macOS 27.0.1 (26A434).
    public static let macOS27 = GlassLook(
        light: .light, dark: .dark,
        lightRim: .light, darkRim: .dark,
        lightSelection: .light, darkSelection: .dark,
        lightTint: .light, darkTint: .dark
    )
}
