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
    /// The glass height the values were fitted at, for tunings whose edge refraction scales with
    /// the glass's height, as SwiftUI's Dock glass does. Nil means the values are absolute.
    public var referenceHeight: Double?

    public init(_ values: [Input: Double], referenceHeight: Double? = nil) {
        self.values = values
        self.referenceHeight = referenceHeight
    }

    /// Inputs that scale with the glass's height when `referenceHeight` is set.
    static let heightScaled: Set<Input> = [.innerRefractionHeight, .innerRefractionAmount]

    /// The values for glass of a given height.
    func values(forHeight height: Double) -> [Input: Double] {
        guard let referenceHeight, referenceHeight > 0, height > 0 else { return values }
        var scaled = values
        for input in Self.heightScaled { scaled[input] = scaled[input].map { $0 * height / referenceHeight } }
        return scaled
    }

    /// macOS 27's switcher in light mode: SwiftUI's Dock glass drawn active, with a shallower,
    /// gentler edge band. The Dock glass scales its edge band with the glass's height (0.08 × and
    /// −0.18 × height); the native switcher's is 0.0751 × and −0.1702 × height. Fitted at the
    /// native 176pt plate, independently in light and dark mode, which agree; everything else is
    /// the Dock glass's own.
    public static let light = GlassTuning([
        .innerRefractionHeight: 13.22,
        .innerRefractionAmount: -29.95,
    ], referenceHeight: 176)

    /// macOS 27's switcher in dark mode; the same values as `light`.
    public static let dark: GlassTuning? = light
}

/// The glass's own specular rim: the key-and-fill highlight SwiftUI draws along the outline of
/// glass in an active window, on a signed-distance-field layer above the backdrop.
///
/// Values are the highlight effect's properties; DockGlass writes only those listed and leaves
/// the rest to the system. An empty highlight keeps the system's rim exactly.
public struct GlassHighlight: Sendable, Equatable {
    public enum Property: String, CaseIterable, Sendable {
        /// Brightness of the key light (from the top) and the fill light (from the bottom).
        case keyAmount, fillAmount
        /// Angular spread of each light around the outline, in radians.
        case keySpread, fillSpread
        /// How far each light reaches in from the outline, relative to the system's.
        case keyHeight, fillHeight
        case curvature
        case diffuseAmountScale, diffuseHeightScale, diffuseSpreadScale
        /// Opacity of each light's colour (white), relative to the system's: the system sets both
        /// to 0 to hide the rim on inactive glass, which an override keeps. An amount of 0 instead
        /// draws a solid band.
        case keyOpacity, fillOpacity

        /// The effect property a value is written to, for the two that live in a colour's alpha.
        var colorKey: String? {
            switch self {
            case .keyOpacity: "keyColor"
            case .fillOpacity: "fillColor"
            default: nil
            }
        }
    }

    public var values: [Property: Double]

    public init(_ values: [Property: Double] = [:]) {
        self.values = values
    }

    /// The system's own rim, unchanged.
    public static let system = GlassHighlight()

    /// The system's values, read on macOS 27.0.1, for scaling a highlight that leaves a
    /// property at the system's value.
    static let systemValues: [Property: Double] = [
        .keyAmount: 0.5, .fillAmount: 0.5, .keySpread: 1.513, .fillSpread: 1.513,
        .keyHeight: 1, .fillHeight: 1, .curvature: 0.75,
        .diffuseAmountScale: 0.15, .diffuseHeightScale: 8, .diffuseSpreadScale: 0.65,
        .keyOpacity: 1, .fillOpacity: 1,
    ]
}

/// A white hairline stroked along the outline, standing in for the specular rim on looks fitted
/// on glass drawn in the inactive state, where the system hides its own rim (macOS 26's look).
public struct GlassRim: Sendable, Equatable {
    public var opacity: Double
    public var width: CGFloat

    public init(opacity: Double, width: CGFloat) {
        self.opacity = opacity
        self.width = width
    }

    public static let light = GlassRim(opacity: 0.275, width: 0.875)
    public static let dark = GlassRim(opacity: 0.175, width: 0.875)
    /// No stroke: the glass's own rim shows instead.
    public static let none = GlassRim(opacity: 0, width: 0)
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

    /// Whether this is the Dock glass's own curve rather than a fill curve.
    let isDockGlassCurve: Bool

    public init(halfwayFillOpacity: Double, halfwayFillBlurRadius: Double) {
        self.halfwayFillOpacity = halfwayFillOpacity
        self.halfwayFillBlurRadius = halfwayFillBlurRadius
        isDockGlassCurve = false
    }

    private init(dockGlassCurve: ()) {
        halfwayFillOpacity = 0
        halfwayFillBlurRadius = Self.fullFillBlurRadius
        isDockGlassCurve = true
    }

    /// The native switcher's response, which has the shape of SwiftUI's Dock glass's own: blur
    /// rises with the slider to tint 0.5, then the frosted fill fades in to full at 1. The native
    /// blur rises to 3.5 rather than the Dock glass's 1.5. Fitted on macOS 27.0.1 in dark mode
    /// at tint 0.25, 0.5, 0.75 and 1 (glass error at most 0.09/255 at each).
    public static let dockGlass = TintResponse(dockGlassCurve: ())

    static let fillOpacityKey = "inputBlurFillNormalOpacity"
    static let fillBlurRadiusKey = "inputBlurFillBlurRadius"
    static let fullFillBlurRadius = 8.0

    /// Filter values for a tint amount in 0...1.
    func values(tint: Double) -> [String: Double] {
        let t = min(1, max(0, tint))
        if isDockGlassCurve {
            // The blur bands switch on with any tint; at 0 the blur radius is 0 and they are off.
            let bands = t > 0 ? [1, 0.5, 0.5, 1] : [0, 0, 0, 0]
            return [
                "inputBlurRadius": 7 * min(t, 0.5),
                "inputBlurOpacity0": bands[0], "inputBlurOpacity1": bands[1],
                "inputBlurOpacity2": bands[2], "inputBlurOpacity3": bands[3],
                Self.fillOpacityKey: max(0, 2 * t - 1),
                Self.fillBlurRadiusKey: t > 0.5 ? Self.fullFillBlurRadius : 0,
            ]
        }
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
    /// The SwiftUI glass a look is drawn on.
    public enum Base: Sendable, Equatable {
        /// Public `.clear` glass.
        case clear
        /// SwiftUI's private Dock glass (`_Glass.dock`), which the native switcher's material is.
        /// Where the running system lacks it, the look cannot apply and stock `.clear` shows.
        case dock
    }

    public var base: Base
    /// The window state the look was fitted in, which `DockGlassStyle.FocusState.native` draws.
    public var fittedFocus: DockGlassStyle.FocusState
    public var light: GlassTuning?
    public var dark: GlassTuning?
    public var lightRim: GlassRim
    public var darkRim: GlassRim
    public var lightSelection: SelectionStyle
    public var darkSelection: SelectionStyle
    public var lightTint: TintResponse
    public var darkTint: TintResponse
    public var lightHighlight: GlassHighlight
    public var darkHighlight: GlassHighlight

    public init(
        base: Base = .clear, fittedFocus: DockGlassStyle.FocusState = .inactive,
        light: GlassTuning?, dark: GlassTuning?,
        lightRim: GlassRim, darkRim: GlassRim,
        lightSelection: SelectionStyle, darkSelection: SelectionStyle,
        lightTint: TintResponse, darkTint: TintResponse,
        lightHighlight: GlassHighlight = .system, darkHighlight: GlassHighlight = .system
    ) {
        self.base = base
        self.fittedFocus = fittedFocus
        self.lightHighlight = lightHighlight
        self.darkHighlight = darkHighlight
        self.light = light
        self.dark = dark
        self.lightRim = lightRim
        self.darkRim = darkRim
        self.lightSelection = lightSelection
        self.darkSelection = darkSelection
        self.lightTint = lightTint
        self.darkTint = darkTint
    }

    /// Fitted on macOS 26.6.1 (25G76) against its own switcher, on `.clear` glass drawn in the
    /// inactive state (the fitting tool's panel was never in an active window), which blurs slightly and bends a
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

    /// Fitted on macOS 27.0.1 (26A434): SwiftUI's Dock glass drawn active, with its own rim and
    /// its own response to the tint slider.
    public static let macOS27 = GlassLook(
        base: .dock, fittedFocus: .active,
        light: .light, dark: .dark,
        lightRim: .none, darkRim: .none,
        lightSelection: .light, darkSelection: .dark,
        lightTint: .dockGlass, darkTint: .dockGlass
    )
}
