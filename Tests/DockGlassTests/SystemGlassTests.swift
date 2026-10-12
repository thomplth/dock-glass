import AppKit
import SwiftUI
import Testing
@testable import DockGlass

@MainActor
final class SystemGlassModel: ObservableObject {
    @Published var material = SystemGlassMaterial.regular
    @Published var style = DockGlassStyle(focusState: .active)
}

/// `systemGlass` beside SwiftUI's own glass of the same material and state, which shows what the
/// system draws at its current tint.
struct SystemGlassProbeView: View {
    @ObservedObject var model: SystemGlassModel

    var body: some View {
        HStack {
            Color.clear.frame(width: 240, height: 120)
                .systemGlass(model.material, in: RoundedRectangle(cornerRadius: 30))
                .dockGlassStyle(model.style)
            Color.clear.frame(width: 240, height: 120)
                .glassEffect(model.material.glass, in: RoundedRectangle(cornerRadius: 30))
                .dockGlassFocusState(model.style.focusState)
        }
    }
}

@MainActor
struct SystemGlassHost {
    let window: NSWindow
    let model = SystemGlassModel()
    let view: SystemGlassView

    init() throws {
        window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 600, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = NSHostingView(rootView: SystemGlassProbeView(model: model))
        window.orderFrontRegardless()
        GlassHost.settle(window)
        guard let found = GlassHost.find(SystemGlassView.self, in: window.contentView) else { throw GlassHost.NotFound(what: "SystemGlassView") }
        view = found
    }

    func settle() { GlassHost.settle(window) }

    /// The backdrop layers of the tuned glass and of SwiftUI's own beside it.
    func layers() throws -> (tuned: CALayer, plain: CALayer) {
        let all = window.contentView?.layer.map(TunedGlassView.backdropLayers(in:)) ?? []
        let tuned = view.layer.map(TunedGlassView.backdropLayers(in:)) ?? []
        guard let first = tuned.first, let plain = all.first(where: { layer in !tuned.contains { $0 === layer } }) else {
            throw GlassHost.NotFound(what: "CABackdropLayer")
        }
        return (first, plain)
    }

    static func number(_ key: String, on layer: CALayer) -> Double? {
        (layer.value(forKeyPath: "filters.glassBackground.\(key)") as? NSNumber)?.doubleValue
    }

    static func fill(on layer: CALayer) -> [Double]? {
        guard let value = layer.value(forKeyPath: "filters.glassBackground.\(SystemTintResponse.fillColorKey)"),
              CFGetTypeID(value as CFTypeRef) == CGColor.typeID else { return nil }
        return (value as! CGColor).components?.map { Double($0) }
    }

    /// Expects the tuned glass to carry a response's values.
    func expect(_ response: SystemTintResponse, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let layer = try layers().tuned
        for (key, expected) in response.numbers {
            let actual = Self.number(key, on: layer)
            #expect(actual.map { abs($0 - expected) < 1e-6 } == true, "\(key): expected \(expected), got \(String(describing: actual))", sourceLocation: sourceLocation)
        }
        if let fill = response.fill {
            let actual = try #require(Self.fill(on: layer), sourceLocation: sourceLocation)
            #expect(abs((actual.last ?? -1) - fill.alpha) < 1e-6 && abs(actual[0] - fill.gray) < 1e-6,
                "fill: expected \(fill), got \(actual)", sourceLocation: sourceLocation)
        }
    }

    /// Expects the tuned glass's tint inputs to equal SwiftUI's own glass beside it.
    func expectSystemTint(sourceLocation: SourceLocation = #_sourceLocation) throws {
        let (tuned, plain) = try layers()
        let keys = SystemTintResponse(material: model.material, isDark: false, active: true, tint: 1).requiredInputs
        for key in keys where key != SystemTintResponse.fillColorKey {
            let (a, b) = (Self.number(key, on: tuned), Self.number(key, on: plain))
            #expect(a != nil && b != nil && abs(a! - b!) < 1e-6, "\(key): tuned \(String(describing: a)), system \(String(describing: b))", sourceLocation: sourceLocation)
        }
        let (a, b) = (Self.fill(on: tuned), Self.fill(on: plain))
        #expect(a != nil && a?.count == b?.count && zip(a!, b ?? []).allSatisfy { abs($0 - $1) < 1e-6 },
            "fill: tuned \(String(describing: a)), system \(String(describing: b))", sourceLocation: sourceLocation)
    }
}

@MainActor
@Suite(.serialized)
struct SystemGlassTests {
    init() {
        _ = NSApplication.shared
        DockGlass.isEnabled = true
        DockGlass.environment = .verified
        SystemGlassView.extraRequiredInputs = []
    }

    /// The system's own tint, which SwiftUI's glass in the test process draws with.
    private var systemTint: Double { UserDefaults.standard.double(forKey: "NSGlassTintAmount") }

    /// Values read back from SwiftUI's glass on macOS 27.0.1, launched with `-NSGlassTintAmount`.
    @Test func responseMatchesMeasuredSystemValues() {
        let regularLight = SystemTintResponse(material: .regular, isDark: false, active: true, tint: 0.75)
        #expect(regularLight.numbers["inputBlurFillNormalOpacity"] == 0.75)
        #expect(regularLight.numbers["inputBlurFillLightenOpacity"] == 0.9)
        #expect(regularLight.fill == .init(gray: 1, alpha: 0.35))
        #expect(abs((SystemTintResponse(material: .regular, isDark: false, active: true, tint: 0.1).numbers["inputBlurFillLightenOpacity"] ?? 0) - 0.72) < 1e-9)
        #expect(SystemTintResponse(material: .regular, isDark: false, active: true, tint: 0.25).fill == .init(gray: 1, alpha: 0.1))

        let regularDark = SystemTintResponse(material: .regular, isDark: true, active: true, tint: 0.9)
        #expect(regularDark.numbers["inputBlurFillDarkenOpacity"] == 0.9)
        #expect(abs((regularDark.fill?.alpha ?? 0) - 0.4) < 1e-9 && abs((regularDark.fill?.gray ?? 0) - 0.1) < 1e-9)
        #expect(abs((SystemTintResponse(material: .regular, isDark: true, active: true, tint: 0.1).numbers["inputFaceColorMatrixMaxLuma"] ?? 0) - 0.43) < 1e-9)

        let clearActive = SystemTintResponse(material: .clear, isDark: false, active: true, tint: 0.25)
        #expect(clearActive.numbers["inputBlurRadius"] == 0.375)
        #expect(clearActive.numbers["inputBlurFillNormalOpacity"] == 0)
        #expect(clearActive.numbers["inputBlurOpacity1"] == 0.5)
        let clearFull = SystemTintResponse(material: .clear, isDark: true, active: true, tint: 0.9)
        #expect(abs((clearFull.numbers["inputBlurFillNormalOpacity"] ?? 0) - 0.8) < 1e-9)
        #expect(clearFull.numbers["inputBlurFillBlurRadius"] == 8)
        #expect(SystemTintResponse(material: .clear, isDark: false, active: true, tint: 0).numbers["inputBlurOpacity0"] == 0)
        #expect(SystemTintResponse(material: .clear, isDark: false, active: nil, tint: 0.25).numbers["inputBlurRadius"] == nil,
            "clear glass's blur depends on the state, so an unknown state leaves it alone")
    }

    /// A fixed tint at the system's own value must draw exactly what SwiftUI draws: the response
    /// is SwiftUI's, not a fit.
    @Test(arguments: [SystemGlassMaterial.regular, .clear], [false, true])
    func fixedTintAtTheSystemValueChangesNothing(material: SystemGlassMaterial, dark: Bool) throws {
        let host = try SystemGlassHost()
        host.window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.model.material = material
        host.model.style = DockGlassStyle(tint: .fixed(systemTint), focusState: .active)
        host.settle()
        try host.expectSystemTint()
    }

    @Test(arguments: [SystemGlassMaterial.regular, .clear])
    func fixedTintWritesTheSystemResponse(material: SystemGlassMaterial) throws {
        let host = try SystemGlassHost()
        host.model.material = material
        let tint = systemTint > 0.5 ? 0.25 : 0.75
        host.model.style = DockGlassStyle(tint: .fixed(tint), focusState: .active)
        host.settle()
        try host.expect(SystemTintResponse(material: material, isDark: false, active: true, tint: tint))
    }

    /// SwiftUI rewrites the filter on every appearance change; the guard must hold the new
    /// appearance's response.
    @Test func holdsTheResponseAcrossAppearanceChanges() throws {
        let host = try SystemGlassHost()
        host.model.style = DockGlassStyle(tint: .fixed(0.75), focusState: .active)
        host.settle()
        host.window.appearance = NSAppearance(named: .darkAqua)
        host.settle()
        try host.expect(SystemTintResponse(material: .regular, isDark: true, active: true, tint: 0.75))
        host.window.appearance = NSAppearance(named: .aqua)
        host.settle()
        try host.expect(SystemTintResponse(material: .regular, isDark: false, active: true, tint: 0.75))
    }

    /// Going back to the system tint hands the glass back, values and all.
    @Test func systemTintLeavesStockGlass() throws {
        let host = try SystemGlassHost()
        host.model.style = DockGlassStyle(tint: .fixed(systemTint > 0.5 ? 0 : 1), focusState: .active)
        host.settle()
        host.model.style = DockGlassStyle(tint: .system, focusState: .active)
        host.settle()
        try host.expectSystemTint()
    }

    @Test func reduceTransparencyLeavesStockGlass() throws {
        DockGlass.environment.reduceTransparency = { true }
        let host = try SystemGlassHost()
        host.model.style = DockGlassStyle(tint: .fixed(systemTint > 0.5 ? 0 : 1), focusState: .active)
        host.settle()
        try host.expectSystemTint()
    }

    @Test func unverifiedSystemLeavesStockGlass() throws {
        DockGlass.environment.majorVersion = { 28 }
        let host = try SystemGlassHost()
        host.model.style = DockGlassStyle(tint: .fixed(systemTint > 0.5 ? 0 : 1), focusState: .active)
        host.settle()
        try host.expectSystemTint()
    }

    /// A filter without an input the response writes (macOS 26 has no fill inputs) must not get
    /// half a response.
    @Test func missingFilterInputLeavesStockGlass() throws {
        SystemGlassView.extraRequiredInputs = ["inputRenamedByAFutureRelease"]
        let host = try SystemGlassHost()
        host.model.style = DockGlassStyle(tint: .fixed(systemTint > 0.5 ? 0 : 1), focusState: .active)
        host.settle()
        try host.expectSystemTint()
    }
}
