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
    public static var fittingRim: GlassRim {
        get { rim }
        set {
            rim = newValue
            NotificationCenter.default.post(name: settingsDidChange, object: nil)
        }
    }
}
