import AppKit

/// Namespace for DockGlass configuration and diagnostics.
@MainActor
public enum DockGlass {
    /// Whether tuned glass is showing, or why the system's stock glass is showing instead.
    public enum Status: Equatable, Sendable {
        case tuned
        case stock(Reason)
    }

    public enum Reason: Error, Equatable, Sendable {
        /// `DockGlass.isEnabled` is false.
        case disabled
        /// The running macOS major version has no verified tuning.
        case unsupportedSystem(majorVersion: Int)
        /// Reduce Transparency is on; the system replaces glass with a frosted, opaque look.
        case reduceTransparency
        /// Increase Contrast is on; the system's high-contrast glass takes precedence.
        case increaseContrast
        /// The current appearance (for example dark mode) has no fitted table yet.
        case noTuningForAppearance
        /// The glass filter lacks inputs DockGlass needs, which means a macOS update changed it.
        case missingFilterInputs([String])
    }

    /// Turns tuning off everywhere. Views fall back to stock `.clear` glass on their next update.
    public static var isEnabled = true {
        didSet { NotificationCenter.default.post(name: settingsDidChange, object: nil) }
    }

    /// The most recently evaluated status, for diagnostics.
    public internal(set) static var status: Status = .stock(.disabled) {
        didSet {
            if status != oldValue { NotificationCenter.default.post(name: statusDidChange, object: nil) }
        }
    }

    /// Posted on the main thread whenever `status` changes.
    public static let statusDidChange = Notification.Name("DockGlassStatusDidChange")

    static let settingsDidChange = Notification.Name("DockGlassSettingsDidChange")

    /// Fitted looks by macOS major version. Each version's switcher and glass filter differ, so a
    /// version without a look renders stock glass.
    static var looks: [Int: GlassLook] = [26: .macOS26, 27: .macOS27]

    /// macOS major versions with a fitted look.
    static var verifiedMajorVersions: Set<Int> { Set(looks.keys) }

    static var environment = SystemEnvironment.live

    /// The running system's look, or the newest fitted one for drawing parts that do not depend on
    /// the glass filter (the selection highlight) when the system has none.
    static var currentLook: GlassLook {
        get { looks[environment.majorVersion()] ?? looks[looks.keys.max() ?? 27] ?? .macOS27 }
        // Never create a look implicitly: that would mark an unverified system as supported.
        set {
            let major = environment.majorVersion()
            guard looks[major] != nil else { return }
            looks[major] = newValue
        }
    }

    /// Tuning per appearance for the running system; injectable so tests can exercise appearance
    /// changes.
    static var tables: (light: GlassTuning?, dark: GlassTuning?) {
        get { (currentLook.light, currentLook.dark) }
        set { currentLook.light = newValue.light; currentLook.dark = newValue.dark }
    }

    static var rims: (light: GlassRim, dark: GlassRim) {
        get { (currentLook.lightRim, currentLook.darkRim) }
        set { currentLook.lightRim = newValue.light; currentLook.darkRim = newValue.dark }
    }

    static var selection: (light: SelectionStyle, dark: SelectionStyle) {
        get { (currentLook.lightSelection, currentLook.darkSelection) }
        set { currentLook.lightSelection = newValue.light; currentLook.darkSelection = newValue.dark }
    }

    static var tintResponses: (light: TintResponse, dark: TintResponse) {
        get { (currentLook.lightTint, currentLook.darkTint) }
        set { currentLook.lightTint = newValue.light; currentLook.darkTint = newValue.dark }
    }

    /// Chooses the tuning for an appearance, or the reason stock glass must show.
    static func resolveTuning(isDark: Bool) -> Result<GlassTuning, Reason> {
        guard isEnabled else { return .failure(.disabled) }
        let major = environment.majorVersion()
        guard verifiedMajorVersions.contains(major) else { return .failure(.unsupportedSystem(majorVersion: major)) }
        if environment.reduceTransparency() { return .failure(.reduceTransparency) }
        if environment.increaseContrast() { return .failure(.increaseContrast) }
        guard let tuning = isDark ? tables.dark : tables.light else { return .failure(.noTuningForAppearance) }
        return .success(tuning)
    }
}

/// System facts DockGlass gates on, injectable so tests can exercise every branch.
struct SystemEnvironment: Sendable {
    var majorVersion: @Sendable () -> Int
    var reduceTransparency: @Sendable @MainActor () -> Bool
    var increaseContrast: @Sendable @MainActor () -> Bool
    /// The Liquid Glass Tint Amount slider, 0 (clear) to 1 (fully tinted).
    var glassTintAmount: @Sendable () -> Double = { UserDefaults.standard.double(forKey: "NSGlassTintAmount") }

    static let live = SystemEnvironment(
        majorVersion: { ProcessInfo.processInfo.operatingSystemVersion.majorVersion },
        reduceTransparency: { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency },
        increaseContrast: { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    )
}
