import AppKit
import SwiftUI
import Testing
@testable import DockGlass

/// These tests render real glass in an off-screen window and read the filter inputs back from the
/// backdrop layer. They need a window server but not Screen Recording.
@MainActor
@Suite(.serialized)
struct TunedGlassTests {
    private static let darkForTests = GlassTuning([
        .blurRadius: 1, .innerRefractionHeight: 9, .innerRefractionAmount: -20,
        .faceColorBlack: 0.1, .faceColorWhite: 0.8, .faceColorSaturation: 1.2,
    ])

    init() {
        _ = NSApplication.shared
        DockGlass.isEnabled = true
        DockGlass.environment = .verified
        DockGlass.tables = (GlassTuning.light, GlassTuning.dark)
        TunedGlassView.extraRequiredInputs = []
    }

    @Test func appliesLightTuning() throws {
        let host = try GlassHost()
        try host.expectTuned(GlassTuning.light)
        #expect(DockGlass.status == .tuned)
    }

    @Test func keepsTuningAcrossContentAndSizeChanges() throws {
        let host = try GlassHost()
        host.model.label = "changed"
        host.model.width = 640
        host.settle()
        try host.expectTuned(GlassTuning.light)
    }

    /// SwiftUI rewrites the filter on every appearance change; the guard must re-assert inside
    /// that commit, for whichever table the new appearance selects.
    @Test func reassertsAcrossAppearanceChanges() throws {
        DockGlass.tables = (GlassTuning.light, Self.darkForTests)
        let host = try GlassHost()
        let layerBefore = try host.backdropLayer()

        host.window.appearance = NSAppearance(named: .darkAqua)
        host.settle()
        try host.expectTuned(Self.darkForTests)

        host.window.appearance = NSAppearance(named: .aqua)
        host.settle()
        try host.expectTuned(GlassTuning.light)
        #expect(try host.backdropLayer() === layerBefore, "appearance changes reuse the layer; the KVO guard did the work")
    }

    @Test func darkWithoutTableFallsBackToStock() throws {
        let host = try GlassHost()
        host.window.appearance = NSAppearance(named: .darkAqua)
        host.settle()
        #expect(DockGlass.status == .stock(.noTuningForAppearance))
        try host.expectStock()

        host.window.appearance = NSAppearance(named: .aqua)
        host.settle()
        try host.expectTuned(GlassTuning.light)
    }

    @Test func reduceTransparencyStepsAside() throws {
        let host = try GlassHost()
        DockGlass.environment.reduceTransparency = { true }
        host.view.refresh()
        host.settle()
        #expect(DockGlass.status == .stock(.reduceTransparency))
        try host.expectStock()

        DockGlass.environment.reduceTransparency = { false }
        host.view.refresh()
        host.settle()
        try host.expectTuned(GlassTuning.light)
    }

    @Test func increaseContrastStepsAside() throws {
        DockGlass.environment.increaseContrast = { true }
        let host = try GlassHost()
        #expect(DockGlass.status == .stock(.increaseContrast))
        try host.expectStock()
    }

    @Test func unverifiedSystemUsesStockGlass() throws {
        DockGlass.environment.majorVersion = { 28 }
        let host = try GlassHost()
        #expect(DockGlass.status == .stock(.unsupportedSystem(majorVersion: 28)))
        try host.expectStock()
    }

    /// A macOS update that renames an input must not silently apply half a tuning.
    @Test func missingFilterInputFallsBackAndReportsIt() throws {
        TunedGlassView.extraRequiredInputs = ["inputRenamedByAFutureRelease"]
        let host = try GlassHost()
        #expect(DockGlass.status == .stock(.missingFilterInputs(["inputRenamedByAFutureRelease"])))
        try host.expectStock()
    }

    /// Disabling rebuilds the glass, which replaces the backdrop layer; re-enabling must find and
    /// tune the new layer.
    @Test func tunesReplacementLayers() throws {
        let host = try GlassHost()
        let original = try host.backdropLayer()
        DockGlass.isEnabled = false
        host.settle()
        try host.expectStock()
        DockGlass.isEnabled = true
        host.settle()
        #expect(try host.backdropLayer() !== original)
        try host.expectTuned(GlassTuning.light)
    }

    @Test func metricsMatchMeasuredNativeGeometry() {
        let metrics = DockGlass.Metrics.standard
        #expect(metrics.plateHeight == 176)
        #expect(metrics.plateCornerRadius == 57.5)
        #expect(metrics.iconSpacing == 32)
        #expect(metrics.iconCanvasSize == 128)
        #expect(metrics.plateWidth(iconCount: 16) == 2187)
        #expect(DockGlass.Metrics(iconSize: 51).plateHeight == 88)
    }
}

extension SystemEnvironment {
    static let verified = SystemEnvironment(majorVersion: { 27 }, reduceTransparency: { false }, increaseContrast: { false })
}

@MainActor
final class GlassModel: ObservableObject {
    @Published var label = "DockGlass"
    @Published var width: CGFloat = 480
}

struct GlassProbeView: View {
    @ObservedObject var model: GlassModel

    var body: some View {
        Text(model.label)
            .frame(width: model.width, height: 176)
            .dockGlass(in: RoundedRectangle(cornerRadius: 57.5, style: .continuous))
    }
}

@MainActor
struct GlassHost {
    let window: NSWindow
    let model = GlassModel()
    let view: TunedGlassView

    struct NotFound: Error { let what: String }

    init() throws {
        window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 800, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: GlassProbeView(model: model))
        window.orderFrontRegardless()
        Self.settle(window)
        guard let found = Self.find(TunedGlassView.self, in: window.contentView) else { throw NotFound(what: "TunedGlassView") }
        view = found
    }

    func settle() { Self.settle(window) }

    static func settle(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }

    func backdropLayer() throws -> CALayer {
        guard let root = view.layer, let layer = TunedGlassView.backdropLayers(in: root).first else { throw NotFound(what: "CABackdropLayer") }
        return layer
    }

    func value(_ input: GlassTuning.Input) throws -> Double? {
        (try backdropLayer().value(forKeyPath: "filters.glassBackground.\(input.rawValue)") as? NSNumber)?.doubleValue
    }

    func expectTuned(_ tuning: GlassTuning, sourceLocation: SourceLocation = #_sourceLocation) throws {
        for (input, expected) in tuning.values {
            let actual = try value(input)
            #expect(actual.map { abs($0 - expected) < 1e-6 } == true, "\(input.rawValue): expected \(expected), got \(String(describing: actual))", sourceLocation: sourceLocation)
        }
    }

    /// Stock `.clear` glass blurs; every DockGlass table sets blur to at most 1.
    func expectStock(sourceLocation: SourceLocation = #_sourceLocation) throws {
        let blur = try value(.blurRadius)
        #expect((blur ?? 0) > 1, "expected stock blur, got \(String(describing: blur))", sourceLocation: sourceLocation)
    }

    static func find<V: NSView>(_ type: V.Type, in root: NSView?) -> V? {
        guard let root else { return nil }
        if let match = root as? V { return match }
        for sub in root.subviews { if let match = find(type, in: sub) { return match } }
        return nil
    }
}
