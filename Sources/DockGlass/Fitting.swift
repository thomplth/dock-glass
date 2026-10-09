import Foundation

/// Hooks for `glass-fit`, which renders the real component while it searches for tuning values.
/// Not part of the stable API.
extension DockGlass {
    @_spi(Fitting)
    public static var fittingTables: (light: GlassTuning?, dark: GlassTuning?) {
        get { tables }
        set {
            tables = newValue
            NotificationCenter.default.post(name: settingsDidChange, object: nil)
        }
    }

    @_spi(Fitting)
    public static var fittingRims: (light: GlassRim, dark: GlassRim) {
        get { rims }
        set {
            rims = newValue
            NotificationCenter.default.post(name: settingsDidChange, object: nil)
        }
    }

    @_spi(Fitting)
    public static var fittingSelection: (light: SelectionStyle, dark: SelectionStyle) {
        get { selection }
        set { selection = newValue }
    }

    @_spi(Fitting)
    public static var fittingTintResponses: (light: TintResponse, dark: TintResponse) {
        get { tintResponses }
        set {
            tintResponses = newValue
            NotificationCenter.default.post(name: settingsDidChange, object: nil)
        }
    }

    /// Lets `glass-fit` tune on a macOS version that has no fitted look yet, starting from the
    /// newest fitted look.
    @_spi(Fitting)
    public static func fittingAdoptLook(forMajorVersion major: Int) {
        guard looks[major] == nil else { return }
        looks[major] = looks[looks.keys.max() ?? 27] ?? .macOS27
        NotificationCenter.default.post(name: settingsDidChange, object: nil)
    }

    /// The look in use on the running system, for printing a fitted table.
    @_spi(Fitting)
    public static var fittingCurrentLook: GlassLook { currentLook }
}
