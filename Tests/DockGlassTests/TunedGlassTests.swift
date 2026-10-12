import AppKit
import SwiftUI
import Testing
@testable import DockGlass

/// These tests render real glass in an off-screen window and read the filter inputs back from the
/// backdrop layer. They need a window server but not Screen Recording.
@MainActor
@Suite(.serialized)
struct TunedGlassTests {
    // No blur: on macOS 27's look the tint curve owns it.
    private static let darkForTests = GlassTuning([
        .innerRefractionHeight: 9, .innerRefractionAmount: -20,
        .faceColorBlack: 0.1, .faceColorWhite: 0.8, .faceColorSaturation: 1.2,
        .faceColorMaxLuma: 0.9, .faceColorMaxLumaSDR: 0.9,
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

    @Test func darkUsesDarkTuning() throws {
        let host = try GlassHost()
        host.window.appearance = NSAppearance(named: .darkAqua)
        host.settle()
        try host.expectTuned(try #require(GlassTuning.dark))
        #expect(DockGlass.status == .tuned)
    }

    @Test func appearanceWithoutTableFallsBackToStock() throws {
        DockGlass.tables = (GlassTuning.light, nil)
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

    @Test func looksAreChosenByMajorVersion() throws {
        let look26 = GlassLook(
            light: GlassTuning([.blurRadius: 3, .innerRefractionHeight: 15, .innerRefractionAmount: -50,
                                .faceColorBlack: 0.15, .faceColorWhite: 0.9, .faceColorSaturation: 1.1]),
            dark: nil,
            lightRim: .light, darkRim: .dark, lightSelection: .light, darkSelection: .dark,
            lightTint: .light, darkTint: .dark
        )
        DockGlass.looks[26] = look26
        defer { DockGlass.looks[26] = .macOS26 }
        DockGlass.environment.majorVersion = { 26 }
        let host = try GlassHost()
        try host.expectTuned(try #require(look26.light))
        #expect(DockGlass.status == .tuned)
    }

    /// Writing tuning on an unverified system must not quietly verify it.
    @Test func writingTablesNeverVerifiesASystem() throws {
        DockGlass.environment.majorVersion = { 28 }
        DockGlass.tables = (GlassTuning.light, GlassTuning.dark)
        #expect(DockGlass.looks[28] == nil)
        let host = try GlassHost()
        #expect(DockGlass.status == .stock(.unsupportedSystem(majorVersion: 28)))
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

    /// macOS 27's look follows the native switcher's tint curve: blur first, then the fill.
    @Test func followsTheNativeTintCurve() throws {
        DockGlass.environment.glassTintAmount = { 0.25 }
        let host = try GlassHost()
        let layer = try host.backdropLayer()
        func input(_ key: String) -> Double? { (layer.value(forKeyPath: "filters.glassBackground.\(key)") as? NSNumber)?.doubleValue }
        #expect(input("inputBlurRadius") == 1.75)
        #expect(input("inputBlurFillNormalOpacity") == 0)

        DockGlass.environment.glassTintAmount = { 0.75 }
        host.view.refresh()
        host.settle()
        #expect(input("inputBlurRadius") == 3.5)
        #expect(input("inputBlurFillNormalOpacity") == 0.5)
        #expect(input("inputBlurFillBlurRadius") == 8)
    }

    /// Clear-based looks (macOS 26's) drive the fill on a fitted curve instead.
    @Test func fillCurveFollowsTintSlider() {
        let response = TintResponse.light
        #expect(response.values(tint: 0.5) == ["inputBlurFillNormalOpacity": response.halfwayFillOpacity, "inputBlurFillBlurRadius": response.halfwayFillBlurRadius])
    }

    @Test func tintCurveMatchesSystemEndpoints() {
        let response = TintResponse.light
        #expect(response.values(tint: 0) == ["inputBlurFillNormalOpacity": 0, "inputBlurFillBlurRadius": 0])
        #expect(response.values(tint: 1) == ["inputBlurFillNormalOpacity": 1, "inputBlurFillBlurRadius": 8])
        #expect(response.values(tint: 0.25)["inputBlurFillNormalOpacity"] == response.halfwayFillOpacity / 2)
    }

    /// A style scales the fitted look; it never replaces the gating or the other inputs.
    @Test func styleScalesEdgeRefraction() throws {
        let host = try GlassHost()
        host.model.style = DockGlassStyle(edgeRefraction: 0.5)
        host.settle()
        var expected = GlassTuning.light
        expected.values[.innerRefractionAmount] = (GlassTuning.light.values[.innerRefractionAmount] ?? 0) * 0.5
        try host.expectTuned(expected)

        host.model.style = .native
        host.settle()
        try host.expectTuned(GlassTuning.light)
    }

    @Test func fixedTintIgnoresSystemSetting() throws {
        DockGlass.environment.glassTintAmount = { 0 }
        let host = try GlassHost()
        host.model.style = DockGlassStyle(tint: .fixed(1))
        host.settle()
        let layer = try host.backdropLayer()
        #expect((layer.value(forKeyPath: "filters.glassBackground.inputBlurFillNormalOpacity") as? NSNumber)?.doubleValue == 1)
    }

    /// A style must not leak past the fallback: stock glass stays stock.
    @Test func styleDoesNotTuneStockGlass() throws {
        DockGlass.environment.reduceTransparency = { true }
        let host = try GlassHost()
        host.model.style = DockGlassStyle(edgeRefraction: 2)
        host.settle()
        #expect(DockGlass.status == .stock(.reduceTransparency))
        try host.expectStock()
    }

    @Test func selectionStrengthScalesTheBlendEffect() {
        let half = DockGlassStyle(selectionStrength: 0.5)
        #expect(abs(half.selection(.light).gray - 0.89) < 1e-9)
        #expect(half.selection(.light).blend == .plusDarker)
        #expect(abs(half.selection(.dark).gray - 0.125) < 1e-9)
        let none = DockGlassStyle(selectionStrength: 0)
        #expect(none.selection(.light).gray == 1, "plus-darker with white is invisible")
        #expect(none.selection(.dark).gray == 0, "plus-lighter with black is invisible")
        #expect(DockGlassStyle(selectionStrength: 10).selection(.light).gray == 0)
    }

    @Test func rimStyleScalesAndClamps() {
        let rim = DockGlassStyle(rimStrength: 2, rimWidth: 2).rim(.light)
        #expect(rim.opacity == 0.55)
        #expect(rim.width == 1.75)
        #expect(DockGlassStyle(rimStrength: 10).rim(.light).opacity == 1)
        #expect(DockGlassStyle(rimStrength: 0).rim(.light).opacity == 0)
    }

    @Test func metricsMatchMeasuredNativeGeometry() {
        let metrics = DockGlass.Metrics.standard
        #expect(metrics.plateHeight == 176)
        #expect(metrics.plateCornerRadius == 58)
        #expect(metrics.iconSpacing == 32)
        #expect(metrics.iconCanvasSize == 128)
        #expect(metrics.plateWidth(iconCount: 16) == 2186)
        #expect(metrics.plateWidth(iconCount: 17) == 2320, "measured on macOS 27.0.1")
        #expect(DockGlass.Metrics(iconSize: 51).plateHeight == 88)
        // Fitted against native label ink on macOS 27.0.1, light and dark.
        #expect(DockGlass.Label.standardFontSize == 12.8125)
        #expect(metrics.labelFontSize == 12.8125)
    }

    /// The label sits on the weight axis between semibold and bold, which only a variation
    /// reaches; a font that silently dropped it would render as plain bold.
    @Test func labelFontUsesFittedWeightAxis() throws {
        let font = DockGlass.Label.nsFont(size: 12.8125)
        let variation = try #require(CTFontCopyVariation(font as CTFont) as? [Int: Double])
        #expect(variation[DockGlass.Label.weightAxisTag] == 680)
        #expect(font.pointSize == 12.8125)
    }
}

extension SystemEnvironment {
    static let verified = SystemEnvironment(
        majorVersion: { 27 }, reduceTransparency: { false }, increaseContrast: { false }, glassTintAmount: { 0 }
    )
}

@MainActor
final class GlassModel: ObservableObject {
    @Published var label = "DockGlass"
    @Published var width: CGFloat = 480
    @Published var height: CGFloat = 176
    @Published var style = DockGlassStyle.native
    /// Shows plain `.clear` glass beside DockGlass, to check DockGlass leaves it alone.
    @Published var showsPlainGlass = false
    /// The state the plain glass is drawn in through the public modifier, or nil for none.
    @Published var plainGlassFocus: DockGlassStyle.FocusState?
}

struct GlassProbeView: View {
    @ObservedObject var model: GlassModel

    var body: some View {
        HStack {
            Text(model.label)
                .frame(width: model.width, height: model.height)
                .dockGlass(in: RoundedRectangle(cornerRadius: 57.5, style: .continuous))
                .dockGlassStyle(model.style)
            if model.showsPlainGlass {
                if let focus = model.plainGlassFocus {
                    Color.clear.frame(width: 120, height: 120).glassEffect(.clear, in: Circle())
                        .dockGlassFocusState(focus)
                } else {
                    Color.clear.frame(width: 120, height: 120).glassEffect(.clear, in: Circle())
                }
            }
        }
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
