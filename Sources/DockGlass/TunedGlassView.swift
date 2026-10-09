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
    private var generation = 0
    private var activeTuning: GlassTuning?
    private var activeRim: GlassRim?
    private var guarded: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var reasserting = false
    private var observers: [NSObjectProtocol] = []

    /// Inputs the tuning requires; tests override this to simulate a changed filter.
    static var requiredInputs: [String] { GlassTuning.Input.allCases.map(\.rawValue) + extraRequiredInputs }
    static var extraRequiredInputs: [String] = []

    init(shape: AnyShape, rimShape: AnyInsettableShape) {
        self.shape = shape
        self.rimShape = rimShape
        hosting = NSHostingView(rootView: AnyView(EmptyView()))
        super.init(frame: .zero)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = bounds
        addSubview(hosting)
        rebuildRootView()

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
        observers.append(NotificationCenter.default.addObserver(
            forName: DockGlass.settingsDidChange, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.refresh() } })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    isolated deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0); NotificationCenter.default.removeObserver($0) }
    }

    func update(shape: AnyShape, rimShape: AnyInsettableShape) {
        self.shape = shape
        self.rimShape = rimShape
        rebuildRootView()
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
            if let missing = Self.missingInputs(in: layers), !missing.isEmpty {
                fallBackToStock(.missingFilterInputs(missing))
                return
            }
            activeTuning = tuning
            setRim(DockGlass.rim)
            for layer in layers {
                apply(tuning, to: layer)
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
        guard let tuning = activeTuning, !reasserting else { return }
        // Writing an input re-posts `filters`; without this guard the handler recurses until the
        // stack overflows.
        reasserting = true
        defer { reasserting = false }
        apply(tuning, to: layer)
    }

    private func apply(_ tuning: GlassTuning, to layer: CALayer) {
        for (input, value) in tuning.values {
            let keyPath = "filters.glassBackground.\(input.rawValue)"
            if (layer.value(forKeyPath: keyPath) as? NSNumber)?.doubleValue != value {
                layer.setValue(value, forKeyPath: keyPath)
            }
        }
    }

    private func fallBackToStock(_ reason: DockGlass.Reason) {
        DockGlass.status = .stock(reason)
        guard activeTuning != nil else { return }
        activeTuning = nil
        guarded.removeAll()
        setRim(nil)
        // Stock values differ by appearance and tint, so rather than restore remembered values,
        // rebuild the glass: SwiftUI creates a fresh backdrop layer with the system's own values.
        generation += 1
        rebuildRootView()
    }

    private func setRim(_ rim: GlassRim?) {
        guard rim != activeRim else { return }
        activeRim = rim
        rebuildRootView()
    }

    private func rebuildRootView() {
        let rim = activeRim
        hosting.rootView = AnyView(
            Color.clear
                .glassEffect(.clear, in: shape)
                .overlay {
                    if let rim {
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

    /// Inputs the tuning needs that the glass filter does not expose, or nil when no glass filter
    /// has been created yet.
    static func missingInputs(in layers: [CALayer]) -> [String]? {
        guard let layer = layers.first else { return nil }
        guard let filter = (layer.filters as? [NSObject])?.first(where: { ($0.value(forKey: "name") as? String) == "glassBackground" }) else {
            return ["glassBackground"]
        }
        let available = Set(filter.value(forKey: "inputKeys") as? [String] ?? [])
        return requiredInputs.filter { !available.contains($0) }
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
