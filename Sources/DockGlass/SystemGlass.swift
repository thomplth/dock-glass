import AppKit
import SwiftUI

/// SwiftUI's own public glass materials, for `systemGlass(_:in:)`.
public enum SystemGlassMaterial: Sendable, Equatable {
    case clear
    case regular

    var glass: Glass { self == .regular ? .regular : .clear }
}

extension View {
    /// Places SwiftUI's own clear or regular glass behind the view, in the given shape, drawn in
    /// the `dockGlassStyle`'s focus state and tint.
    ///
    /// The glass is stock: only the style's `focusState` and `tint` apply. With `.system` tint it
    /// is exactly `glassEffect`. A `.fixed` tint draws what SwiftUI itself draws with the Liquid
    /// Glass Tint Amount slider at that value, whatever the system setting. The fixed tint needs a
    /// forced focus state for clear glass, whose blur follows the slider only while active; under
    /// `.matchWindow` that blur keeps the system's value. Where the response is unverified, or
    /// with Reduce Transparency or Increase Contrast on, the glass follows the system tint.
    public func systemGlass<S: InsettableShape>(_ material: SystemGlassMaterial, in shape: S) -> some View {
        background(SystemGlass(material: material, shape: AnyShape(shape)))
    }
}

struct SystemGlass: NSViewRepresentable {
    let material: SystemGlassMaterial
    let shape: AnyShape

    func makeNSView(context: Context) -> SystemGlassView {
        SystemGlassView(material: material, shape: shape, style: context.environment.dockGlassStyle)
    }

    func updateNSView(_ view: SystemGlassView, context: Context) {
        view.update(material: material, shape: shape, style: context.environment.dockGlassStyle)
    }
}

/// How SwiftUI's clear and regular glass follow the Liquid Glass Tint Amount slider.
///
/// Measured on macOS 27.0.1 by launching a probe with `-NSGlassTintAmount` at 0, 0.1, 0.25, 0.5,
/// 0.75, 0.9 and 1, in light and dark, active and inactive, and reading the `glassBackground`
/// filter back (Docs/FINDINGS.md). Every other input is the same at every tint.
struct SystemTintResponse {
    /// macOS major versions the response was measured on. macOS 26's filter lacks the fill inputs.
    static let verifiedMajorVersions: Set<Int> = [27]

    static let fillColorKey = "inputFaceColorMatrixFillColor"

    /// A grey fill colour, written in the colour space of the one SwiftUI set.
    struct Fill: Equatable {
        var gray: Double
        var alpha: Double
    }

    var numbers: [String: Double]
    var fill: Fill?

    /// The values for a tint amount. `active` is nil when the focus state is unknown, which leaves
    /// clear glass's state-dependent blur alone.
    init(material: SystemGlassMaterial, isDark: Bool, active: Bool?, tint: Double) {
        let t = min(1, max(0, tint))
        let firstHalf = min(t, 0.5)
        switch material {
        case .clear:
            numbers = [
                TintResponse.fillOpacityKey: max(0, 2 * t - 1),
                TintResponse.fillBlurRadiusKey: t > 0.5 ? TintResponse.fullFillBlurRadius : 0,
            ]
            if active == true {
                // Active clear glass blurs with the first half of the slider, like the Dock glass.
                let bands = t > 0 ? [1, 0.5, 0.5, 1] : [0, 0, 0, 0]
                numbers["inputBlurRadius"] = 1.5 * firstHalf
                for (index, opacity) in bands.enumerated() { numbers["inputBlurOpacity\(index)"] = opacity }
            }
            fill = nil
        case .regular:
            // Both appearances write the same inputs, so nothing written in one survives a switch
            // to the other. Light mode lightens the fill and dark mode darkens it.
            let fillBlend = 0.675 + 0.45 * firstHalf
            numbers = [
                TintResponse.fillOpacityKey: t,
                "inputBlurFillLightenOpacity": isDark ? 0 : fillBlend,
                "inputBlurFillDarkenOpacity": isDark ? fillBlend : 0,
                "inputFaceColorMatrixMaxLuma": isDark ? 0.45 - 0.2 * firstHalf : 1,
                "inputFaceColorMatrixMaxLumaSDR": isDark ? 0.45 - 0.2 * firstHalf : 0.94,
            ]
            fill = isDark
                ? Fill(gray: 0.125 * abs(1 - 2 * t), alpha: max(0, t - 0.5))
                : Fill(gray: 1, alpha: t <= 0.5 ? 0.4 * t : 0.2 + 0.6 * (t - 0.5))
        }
    }

    /// Every input the response writes on some tint, for checking the filter has them.
    var requiredInputs: [String] {
        Array(numbers.keys) + (fill == nil ? [] : [Self.fillColorKey])
    }
}

/// Hosts SwiftUI's own clear or regular glass in its own layer subtree and, for a fixed tint,
/// holds the tint-driven filter inputs at the system's response to that tint. The same guard as
/// `TunedGlassView` re-asserts them when SwiftUI rewrites the filter.
@MainActor
final class SystemGlassView: NSView {
    private let hosting: NSHostingView<AnyView>
    private var material: SystemGlassMaterial
    private var shape: AnyShape
    private var style: DockGlassStyle
    private var generation = 0
    /// The response currently held on the glass; nil leaves the system's own tint.
    private var activeResponse: SystemTintResponse?
    private var guarded: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var reasserting = false
    private var observers: [NSObjectProtocol] = []

    /// Inputs a fixed tint requires beyond the response's own; tests simulate a changed filter.
    static var extraRequiredInputs: [String] = []

    init(material: SystemGlassMaterial, shape: AnyShape, style: DockGlassStyle) {
        self.material = material
        self.shape = shape
        self.style = style
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: .zero)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = bounds
        addSubview(hosting)
        rebuildRootView()

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: DockGlass.settingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            NotificationCenter.default.removeObserver($0)
        }
    }

    func update(material: SystemGlassMaterial, shape: AnyShape, style: DockGlassStyle) {
        let changed = material != self.material || style != self.style
        self.material = material
        self.shape = shape
        self.style = style
        rebuildRootView()
        guard changed else { return }
        // A new material or state is new glass with new layers: let SwiftUI build them now, then
        // hold those.
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        refresh()
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

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The state the glass draws in, or nil when it follows its window.
    private var focus: DockGlassStyle.FocusState {
        DockGlass.canOverrideFocusState ? style.focusState.resolved : .matchWindow
    }

    /// The response a fixed tint asks for, or nil when the glass should follow the system tint.
    private var wantedResponse: SystemTintResponse? {
        guard case .fixed(let tint) = style.tint, DockGlass.isEnabled,
              SystemTintResponse.verifiedMajorVersions.contains(DockGlass.environment.majorVersion()),
              !DockGlass.environment.reduceTransparency(), !DockGlass.environment.increaseContrast()
        else { return nil }
        let active: Bool? = switch focus {
        case .active: true
        case .inactive: false
        case .matchWindow, .native: nil
        }
        return SystemTintResponse(material: material, isDark: isDark, active: active, tint: tint)
    }

    func refresh() {
        let layers = hosting.layer.map(TunedGlassView.backdropLayers(in:)) ?? []
        guarded = guarded.filter { id, _ in layers.contains { ObjectIdentifier($0) == id } }
        guard let response = wantedResponse else { return release() }
        if let layer = layers.first {
            let available = TunedGlassView.filterInputs(of: layer)
            guard (response.requiredInputs + Self.extraRequiredInputs).allSatisfy(available.contains) else { return release() }
        }
        activeResponse = response
        for layer in layers {
            apply(response, to: layer)
            guard guarded[ObjectIdentifier(layer)] == nil else { continue }
            guarded[ObjectIdentifier(layer)] = layer.observe(\.filters, options: [.new]) { [weak self] layer, _ in
                // Core Animation posts this on the main thread, inside SwiftUI's commit.
                nonisolated(unsafe) let layer = layer
                MainActor.assumeIsolated { self?.filtersDidChange(on: layer) }
            }
        }
    }

    /// Hands the tint back to the system. Rebuilding the glass gives a fresh backdrop layer with
    /// the system's own values, rather than restoring remembered ones.
    private func release() {
        guard activeResponse != nil else { return }
        activeResponse = nil
        guarded.removeAll()
        generation += 1
        rebuildRootView()
    }

    private func filtersDidChange(on layer: CALayer) {
        guard let response = activeResponse, !reasserting else { return }
        // Writing an input re-posts `filters`; without this guard the handler recurses.
        reasserting = true
        defer { reasserting = false }
        apply(response, to: layer)
    }

    private func apply(_ response: SystemTintResponse, to layer: CALayer) {
        for (key, value) in response.numbers {
            let keyPath = "filters.glassBackground.\(key)"
            // The filter stores inputs as floats, so compare at float precision.
            if (layer.value(forKeyPath: keyPath) as? NSNumber)?.floatValue != Float(value) {
                layer.setValue(value, forKeyPath: keyPath)
            }
        }
        guard let fill = response.fill else { return }
        let keyPath = "filters.glassBackground.\(SystemTintResponse.fillColorKey)"
        let current = layer.value(forKeyPath: keyPath).flatMap { value -> CGColor? in
            CFGetTypeID(value as CFTypeRef) == CGColor.typeID ? (value as! CGColor) : nil
        }
        let space = current?.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let components = space.numberOfComponents == 1 ? [fill.gray, fill.alpha] : [fill.gray, fill.gray, fill.gray, fill.alpha]
        guard let color = CGColor(colorSpace: space, components: components.map { CGFloat($0) }) else { return }
        if current.map({ $0 != color }) ?? true {
            layer.setValue(color, forKeyPath: keyPath)
        }
    }

    private func rebuildRootView() {
        hosting.rootView = AnyView(
            Color.clear
                .glassEffect(material.glass, in: shape)
                .dockGlassFocusState(focus)
                .id(generation)
        )
    }
}
