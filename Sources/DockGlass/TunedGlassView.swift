import AppKit
import SwiftUI

/// Hosts SwiftUI `.clear` glass in its own layer subtree so DockGlass can find the backdrop layer
/// the glass renders through and hold its filter inputs at the tuned values.
///
/// SwiftUI rewrites those inputs whenever it re-resolves the glass, notably on every appearance
/// change, and replaces the backdrop layer when the glass is rebuilt. The view therefore
/// rediscovers layers on layout and appearance changes, and observes each layer's `filters` to
/// re-assert the tuning inside the same transaction SwiftUI commits its reset in.
@MainActor
final class TunedGlassView: NSView {
    private let hosting: NSHostingView<AnyView>
    private var shape: AnyShape
    private var rimShape: AnyInsettableShape
    private var style: DockGlassStyle
    private var generation = 0
    /// Filter values currently held on the glass: the appearance's tuning plus the tint fill.
    private var activeValues: [String: Double]?
    private var activeRim: GlassRim?
    /// The look's base glass and resolved focus while tuned; nil shows stock `.clear` glass.
    private var activeGlass: (base: GlassLook.Base, focus: DockGlassStyle.FocusState)?
    /// Highlight values currently held on the glass's specular rim.
    private var activeHighlight: [String: Double]?
    private var guardedEffects: [ObjectIdentifier: EffectObserver] = [:]
    /// Each rim layer's own values, read whenever SwiftUI sets its effect, so a property DockGlass
    /// stops overriding goes back to the system's value and opacity overrides stay relative to it.
    private var systemHighlights: [ObjectIdentifier: [String: Double]] = [:]
    /// Properties DockGlass has written to each rim layer.
    private var writtenHighlights: [ObjectIdentifier: Set<String>] = [:]
    private var guarded: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var reasserting = false
    private var observers: [NSObjectProtocol] = []

    /// Inputs the tuning requires; tests override this to simulate a changed filter.
    static var requiredInputs: [String] {
        GlassTuning.Input.core.map(\.rawValue) + extraRequiredInputs
    }
    static var extraRequiredInputs: [String] = []

    init(shape: AnyShape, rimShape: AnyInsettableShape, style: DockGlassStyle = .native) {
        self.shape = shape
        self.rimShape = rimShape
        self.style = style
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: .zero)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = bounds
        addSubview(hosting)
        // Start on the look's glass, so the first frame is not stock glass rebuilt a turn later.
        if case .success = DockGlass.resolveTuning(isDark: isDark),
           case .success(let glass) = Self.glass(for: DockGlass.currentLook, style: style) {
            activeGlass = glass
        }
        rebuildRootView()

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: DockGlass.settingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        // The window server broadcasts this when the Liquid Glass tint changes.
        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Self.glassAppearanceDidChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        // Observing the defaults key directly fires for writes from other processes, including
        // System Settings.
        tintObservation = UserDefaults.standard.observe(\.NSGlassTintAmount, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    static let glassAppearanceDidChange = Notification.Name("kSLSCoordinatedGlassAppearanceSettingsChangeNotificationName")
    private var tintObservation: NSKeyValueObservation?

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
    }

    func update(shape: AnyShape, rimShape: AnyInsettableShape, style: DockGlassStyle = .native) {
        self.shape = shape
        self.rimShape = rimShape
        let styleChanged = style != self.style
        self.style = style
        rebuildRootView()
        if styleChanged { refresh() }
    }

    override func layout() {
        super.layout()
        hosting.frame = bounds
        refresh()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    // MARK: - Tuning

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Re-evaluates gating and makes every current backdrop layer match it.
    func refresh() {
        let resolved = DockGlass.resolveTuning(isDark: isDark)
        let layers = hosting.layer.map(Self.backdropLayers(in:)) ?? []
        guarded = guarded.filter { id, _ in layers.contains { ObjectIdentifier($0) == id } }

        switch resolved {
        case .success(let tuning):
            let look = DockGlass.currentLook
            let glass: (base: GlassLook.Base, focus: DockGlassStyle.FocusState)
            switch Self.glass(for: look, style: style) {
            case .success(let resolved): glass = resolved
            case .failure(let reason):
                fallBackToStock(reason)
                return
            }
            if setGlass(glass) {
                // The new glass has new layers: let SwiftUI build them now, then tune those.
                hosting.layoutSubtreeIfNeeded()
                hosting.displayIfNeeded()
                refresh()
                return
            }
            if let missing = Self.missingInputs(in: layers), !missing.isEmpty {
                fallBackToStock(.missingFilterInputs(missing))
                return
            }
            let response = isDark ? DockGlass.tintResponses.dark : DockGlass.tintResponses.light
            let styled = style.tuning(tuning)
            var values = Dictionary(uniqueKeysWithValues: styled.values(forHeight: bounds.height).map { ($0.key.rawValue, $0.value) })
            if !DockGlass.skipsTintResponse {
                values.merge(response.values(tint: style.tintAmount(system: DockGlass.environment.glassTintAmount))) { $1 }
            }
            activeValues = values
            setRim(style.rim(isDark ? DockGlass.rims.dark : DockGlass.rims.light))
            let highlight = style.highlight(isDark ? look.darkHighlight : look.lightHighlight)
            activeHighlight = Dictionary(uniqueKeysWithValues: highlight.values.map { ($0.key.rawValue, $0.value) })
            let rimLayers = hosting.layer.map(Self.highlightLayers(in:)) ?? []
            guardedEffects = guardedEffects.filter { id, _ in rimLayers.contains { ObjectIdentifier($0) == id } }
            systemHighlights = systemHighlights.filter { id, _ in rimLayers.contains { ObjectIdentifier($0) == id } }
            writtenHighlights = writtenHighlights.filter { id, _ in rimLayers.contains { ObjectIdentifier($0) == id } }
            for layer in rimLayers {
                applyHighlight(to: layer, systemChanged: systemHighlights[ObjectIdentifier(layer)] == nil)
                guard guardedEffects[ObjectIdentifier(layer)] == nil else { continue }
                guardedEffects[ObjectIdentifier(layer)] = EffectObserver(layer: layer) { [weak self] layer in
                    MainActor.assumeIsolated { self?.effectDidChange(on: layer) }
                }
            }
            for layer in layers {
                apply(values, to: layer)
                guard guarded[ObjectIdentifier(layer)] == nil else { continue }
                guarded[ObjectIdentifier(layer)] = layer.observe(\.filters, options: [.new]) { [weak self] layer, _ in
                    // Core Animation posts this on the main thread, inside SwiftUI's commit.
                    nonisolated(unsafe) let layer = layer
                    MainActor.assumeIsolated { self?.filtersDidChange(on: layer) }
                }
            }
            // Only report tuned once glass exists to tune; before the first layout there is none.
            if !layers.isEmpty { DockGlass.status = .tuned }
        case .failure(let reason):
            fallBackToStock(reason)
        }
    }

    private func filtersDidChange(on layer: CALayer) {
        guard let values = activeValues, !reasserting else { return }
        // Writing an input re-posts `filters`; without this guard the handler recurses until the
        // stack overflows.
        reasserting = true
        defer { reasserting = false }
        apply(values, to: layer)
    }

    private func apply(_ values: [String: Double], to layer: CALayer) {
        // Optional inputs (newer filters only) are skipped where the filter lacks them; writing
        // one would be a silent no-op anyway.
        let available = Self.filterInputs(of: layer)
        for (key, value) in values where available.contains(key) {
            let keyPath = "filters.glassBackground.\(key)"
            if (layer.value(forKeyPath: keyPath) as? NSNumber)?.doubleValue != value {
                layer.setValue(value, forKeyPath: keyPath)
            }
        }
    }

    /// SwiftUI set a new effect, carrying the system's values for the current state.
    private func effectDidChange(on layer: CALayer) {
        guard !reasserting else { return }
        applyHighlight(to: layer, systemChanged: true)
    }

    /// Writes the highlight onto the rim's effect: the overridden properties, and the system's
    /// value for any property DockGlass overrode before but no longer does. Opacities scale the
    /// system's own, so a rim the system hides (inactive glass) stays hidden.
    ///
    /// Core Animation never renders a change made to the layer's current effect in place, so this
    /// assigns a modified copy, and only when a value differs: assigning re-posts `effect`.
    private func applyHighlight(to layer: CALayer, systemChanged: Bool = false) {
        guard let overrides = activeHighlight, let current = Self.highlightEffect(of: layer) else { return }
        let id = ObjectIdentifier(layer)
        if systemChanged {
            systemHighlights[id] = Dictionary(uniqueKeysWithValues: GlassHighlight.Property.allCases.compactMap { property in
                Self.highlightValue(property, of: current).map { (property.rawValue, $0) }
            })
        }
        let system = systemHighlights[id] ?? [:]
        var values = overrides
        for key in [GlassHighlight.Property.keyOpacity, .fillOpacity].map(\.rawValue) {
            if let factor = overrides[key] { values[key] = factor * (system[key] ?? 1) }
        }
        for key in writtenHighlights[id, default: []] where overrides[key] == nil {
            values[key] = system[key]
        }
        writtenHighlights[id] = Set(overrides.keys)
        let changed = values.compactMap { key, value -> (GlassHighlight.Property, Double)? in
            guard let property = GlassHighlight.Property(rawValue: key), Self.supports(property, on: current),
                  Self.highlightValue(property, of: current) != value else { return nil }
            return (property, value)
        }
        guard !changed.isEmpty, let effect = current.copy() as? NSObject else { return }
        for (property, value) in changed {
            if let colorKey = property.colorKey {
                effect.setValue(CGColor(gray: 1, alpha: value), forKey: colorKey)
            } else {
                effect.setValue(value, forKey: property.rawValue)
            }
        }
        reasserting = true
        defer { reasserting = false }
        layer.setValue(effect, forKey: "effect")
    }

    /// Whether an effect has a highlight property. macOS 26's effect lacks the `diffuse` ones,
    /// and key-value coding throws on a key the object lacks, which Swift cannot catch.
    static func supports(_ property: GlassHighlight.Property, on effect: NSObject) -> Bool {
        effect.responds(to: NSSelectorFromString(property.colorKey ?? property.rawValue))
    }

    /// A highlight property's current value on an effect, or nil when the effect lacks it.
    static func highlightValue(_ property: GlassHighlight.Property, of effect: NSObject) -> Double? {
        guard supports(property, on: effect) else { return nil }
        if let colorKey = property.colorKey {
            guard let value = effect.value(forKey: colorKey), CFGetTypeID(value as CFTypeRef) == CGColor.typeID else { return nil }
            return Double((value as! CGColor).alpha)
        }
        return (effect.value(forKey: property.rawValue) as? NSNumber)?.doubleValue
    }

    private func fallBackToStock(_ reason: DockGlass.Reason) {
        DockGlass.status = .stock(reason)
        guard activeValues != nil || activeGlass != nil else { return }
        activeValues = nil
        activeHighlight = nil
        activeGlass = nil
        guarded.removeAll()
        guardedEffects.removeAll()
        systemHighlights.removeAll()
        writtenHighlights.removeAll()
        setRim(nil)
        // Stock values differ by appearance and tint, so rather than restore remembered values,
        // rebuild the glass: SwiftUI creates a fresh backdrop layer with the system's own values.
        generation += 1
        rebuildRootView()
    }

    /// The glass a look draws on and the state it draws in, or why it cannot.
    static func glass(for look: GlassLook, style: DockGlassStyle) -> Result<(base: GlassLook.Base, focus: DockGlassStyle.FocusState), DockGlass.Reason> {
        if look.base == .dock, DockGlass.dockGlass == nil { return .failure(.missingDockGlass) }
        let focus = style.focusState == .native ? look.fittedFocus : style.focusState
        if focus != .matchWindow, !DockGlass.canOverrideFocusState { return .failure(.focusStateUnavailable) }
        return .success((look.base, focus))
    }

    /// Switches the glass SwiftUI draws. Returns whether it changed: SwiftUI then replaces the
    /// backdrop and rim layers on its next update.
    private func setGlass(_ glass: (base: GlassLook.Base, focus: DockGlassStyle.FocusState)) -> Bool {
        guard activeGlass.map({ $0.base != glass.base || $0.focus != glass.focus }) ?? true else { return false }
        activeGlass = glass
        rebuildRootView()
        return true
    }

    private func setRim(_ rim: GlassRim?) {
        guard rim != activeRim else { return }
        activeRim = rim
        rebuildRootView()
    }

    private func rebuildRootView() {
        let rim = activeRim
        let glass = activeGlass
        hosting.rootView = AnyView(
            Color.clear
                .glassEffect(glass?.base == .dock ? DockGlass.dockGlass ?? .clear : .clear, in: shape)
                .dockGlassFocusState(glass?.focus ?? .matchWindow)
                .overlay {
                    if let rim, rim.opacity > 0, rim.width > 0 {
                        rimShape.strokeBorder(.white.opacity(rim.opacity), lineWidth: rim.width)
                            .blendMode(.plusLighter)
                    }
                }
                .id(generation)
        )
    }

    // MARK: - Layer discovery

    static func backdropLayers(in root: CALayer) -> [CALayer] {
        var found: [CALayer] = []
        var stack = [root]
        while let layer = stack.popLast() {
            if NSStringFromClass(type(of: layer)) == "CABackdropLayer" { found.append(layer) }
            stack.append(contentsOf: layer.sublayers ?? [])
        }
        return found
    }

    /// Layers drawing the glass's specular rim: SDF layers whose effect is the key-and-fill
    /// highlight.
    static func highlightLayers(in root: CALayer) -> [CALayer] {
        var found: [CALayer] = []
        var stack = [root]
        while let layer = stack.popLast() {
            if NSStringFromClass(type(of: layer)) == "CASDFLayer", highlightEffect(of: layer) != nil { found.append(layer) }
            stack.append(contentsOf: layer.sublayers ?? [])
        }
        return found
    }

    static func highlightEffect(of layer: CALayer) -> NSObject? {
        guard layer.responds(to: NSSelectorFromString("effect")),
              let effect = layer.value(forKey: "effect") as? NSObject,
              NSStringFromClass(type(of: effect)) == "CASDFKeyFillHighlightEffect" else { return nil }
        return effect
    }

    /// Inputs the tuning needs that the glass filter does not expose, or nil when no glass filter
    /// has been created yet.
    static func missingInputs(in layers: [CALayer]) -> [String]? {
        guard let layer = layers.first else { return nil }
        let available = filterInputs(of: layer)
        guard !available.isEmpty else { return ["glassBackground"] }
        return requiredInputs.filter { !available.contains($0) }
    }

    static func filterInputs(of layer: CALayer) -> Set<String> {
        guard let filter = (layer.filters as? [NSObject])?.first(where: { ($0.value(forKey: "name") as? String) == "glassBackground" }) else {
            return []
        }
        return Set(filter.value(forKey: "inputKeys") as? [String] ?? [])
    }
}

/// Observes a layer's `effect`, which SwiftUI replaces when it re-resolves the glass.
private final class EffectObserver: NSObject {
    private weak var layer: CALayer?
    private let onChange: (CALayer) -> Void

    init(layer: CALayer, onChange: @escaping (CALayer) -> Void) {
        self.layer = layer
        self.onChange = onChange
        super.init()
        layer.addObserver(self, forKeyPath: "effect", options: [.new], context: nil)
    }

    deinit { layer?.removeObserver(self, forKeyPath: "effect") }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard let layer else { return }
        onChange(layer)
    }
}

/// Type-erased insettable shape, so the rim can stroke inside the same outline as the glass.
struct AnyInsettableShape: InsettableShape {
    private let pathBuilder: @Sendable (CGRect) -> Path
    private let insetBuilder: @Sendable (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        pathBuilder = { shape.path(in: $0) }
        insetBuilder = { AnyInsettableShape(shape.inset(by: $0)) }
    }

    func path(in rect: CGRect) -> Path { pathBuilder(rect) }
    func inset(by amount: CGFloat) -> AnyInsettableShape { insetBuilder(amount) }
}

extension UserDefaults {
    /// The global Liquid Glass tint setting, named after its defaults key so KVO observes that key.
    @objc dynamic var NSGlassTintAmount: Double { double(forKey: "NSGlassTintAmount") }
}
