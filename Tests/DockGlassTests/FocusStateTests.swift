import AppKit
import SwiftUI
import Testing
@testable import DockGlass

/// The test host's window is never key in an active app, so glass that follows its window draws
/// inactive. The system hides the specular rim in that state (its layer's opacity drops to 0),
/// which makes the rim layer a readable witness of the state the glass drew in.
extension TunedGlassTests {
    @Test func drawsActiveInAnInactiveWindowByDefault() throws {
        try #require(DockGlass.canOverrideFocusState)
        let host = try GlassHost()
        #expect(!host.window.isKeyWindow)
        #expect(try host.rimOpacity() == 1, "macOS 27's look is fitted active and must draw active anywhere")
        #expect(try host.value(.blurRadius) == 0)
        #expect(DockGlass.status == .tuned)
    }

    @Test func eachFocusStateDrawsAsAsked() throws {
        try #require(DockGlass.canOverrideFocusState)
        let host = try GlassHost()
        host.model.style = DockGlassStyle(focusState: .inactive)
        host.settle()
        #expect(try host.rimOpacity() == 0)
        host.model.style = DockGlassStyle(focusState: .matchWindow)
        host.settle()
        #expect(try host.rimOpacity() == 0, "the host window is inactive")
        host.model.style = DockGlassStyle(focusState: .active)
        host.settle()
        #expect(try host.rimOpacity() == 1)
        // The tuning holds in every state.
        try host.expectTuned(GlassTuning.light)
    }

    /// The private switch is scoped to DockGlass's own subtree: the host's other glass keeps
    /// following the window.
    @Test func forcingFocusLeavesOtherGlassAlone() throws {
        let host = try GlassHost()
        host.model.showsPlainGlass = true
        host.settle()
        let plain = try #require(host.plainGlassRimOpacity())
        #expect(plain == 0)
        #expect(try host.rimOpacity() == 1)
    }

    @Test func missingFocusSwitchFallsBackToStock() throws {
        DockGlass.environment.canOverrideFocusState = { false }
        let host = try GlassHost()
        #expect(DockGlass.status == .stock(.focusStateUnavailable))
        try host.expectStock()

        // Following the window needs no switch, so it still tunes.
        host.model.style = DockGlassStyle(focusState: .matchWindow)
        host.settle()
        #expect(DockGlass.status == .tuned)
        try host.expectTuned(GlassTuning.light)
    }

    @Test func missingDockGlassFallsBackToStock() throws {
        DockGlass.environment.hasDockGlass = { false }
        let host = try GlassHost()
        #expect(DockGlass.status == .stock(.missingDockGlass))
        try host.expectStock()
    }

    /// The Dock glass's own values, which only show when DockGlass draws on it.
    @Test func drawsOnTheDockGlass() throws {
        let host = try GlassHost()
        #expect(try host.value(.faceColorSaturation) == 1.25)
        host.window.appearance = NSAppearance(named: .darkAqua)
        host.settle()
        // Stock `.clear` keeps 1 in dark mode; the Dock glass caps brightness lower.
        #expect(try host.value(.faceColorMaxLuma) == 0.75)
    }

    /// The Dock glass scales its edge band with the glass's height, and so does the tuning.
    @Test func refractionScalesWithHeight() throws {
        let host = try GlassHost()
        host.model.height = 88
        host.settle()
        #expect(try host.value(.innerRefractionHeight).map { abs($0 - 6.61) < 1e-6 } == true)
        #expect(try host.value(.innerRefractionAmount).map { abs($0 + 14.975) < 1e-6 } == true)
    }

    @Test func pinsTheHighlightAcrossAppearanceChanges() throws {
        var look = DockGlass.currentLook
        look.lightHighlight = GlassHighlight([.keyAmount: 0.7])
        look.darkHighlight = GlassHighlight([.keyAmount: 0.3])
        DockGlass.currentLook = look
        defer { DockGlass.looks[27] = .macOS27 }
        let host = try GlassHost()
        #expect(try host.highlight("keyAmount") == 0.7)
        host.window.appearance = NSAppearance(named: .darkAqua)
        host.settle()
        #expect(try host.highlight("keyAmount") == 0.3)
        host.window.appearance = NSAppearance(named: .aqua)
        host.settle()
        #expect(try host.highlight("keyAmount") == 0.7)
    }

    /// SwiftUI replaces the rim's effect whenever it re-resolves the glass, for example when a
    /// window it follows changes state, without any event DockGlass refreshes on.
    @Test func reassertsTheHighlightWhenSwiftUIReplacesIt() throws {
        var look = DockGlass.currentLook
        look.lightHighlight = GlassHighlight([.keyAmount: 0.7])
        DockGlass.currentLook = look
        defer { DockGlass.looks[27] = .macOS27 }
        let host = try GlassHost()
        let layer = try host.rimLayer()
        let replacement = try #require(TunedGlassView.highlightEffect(of: layer)?.copy() as? NSObject)
        replacement.setValue(0.5, forKey: "keyAmount")
        layer.setValue(replacement, forKey: "effect")
        #expect(try host.highlight("keyAmount") == 0.7)
    }

    /// Following the window, the system's own rim must come and go with the window's state, even
    /// with an override in place and after DockGlass first saw the rim hidden.
    @Test func matchWindowKeepsTheSystemsRimState() throws {
        let host = try GlassHost()
        host.model.style = DockGlassStyle(rimStrength: 0.5, focusState: .matchWindow)
        host.settle()
        #expect(try host.highlight(.keyOpacity) == 0, "inactive: the system hides the rim")
        // The window becoming active, as SwiftUI sees it.
        host.model.style = DockGlassStyle(rimStrength: 0.5, focusState: .active)
        host.settle()
        #expect(try host.highlight(.keyOpacity) == 0.5)
        host.model.style = DockGlassStyle(focusState: .active)
        host.settle()
        #expect(try host.highlight(.keyOpacity) == 1)
    }

    /// macOS 26's rim lacks the `diffuse` properties, and reading a key an object lacks throws
    /// an exception that crashes the app.
    @Test func skipsHighlightPropertiesTheRimLacks() {
        let older = NSObject()
        for property in GlassHighlight.Property.allCases {
            #expect(!TunedGlassView.supports(property, on: older))
            #expect(TunedGlassView.highlightValue(property, of: older) == nil)
        }
    }

    @Test func rimStyleScalesTheSystemRim() throws {
        let host = try GlassHost()
        host.model.style = DockGlassStyle(rimStrength: 0.5, rimWidth: 2)
        host.settle()
        #expect(try host.highlight(.keyOpacity) == 0.5)
        #expect(try host.highlight(.fillOpacity) == 0.5)
        #expect(try host.highlight("keyAmount") == 0.5)
        #expect(try host.highlight("keyHeight") == 2)
        host.model.style = DockGlassStyle(rimStrength: 2)
        host.settle()
        #expect(try host.highlight(.keyOpacity) == 1)
        #expect(try host.highlight("keyAmount") == 1)
        // 0 hides the rim the way the system does, never through a zero amount.
        host.model.style = DockGlassStyle(rimStrength: 0, rimWidth: 0)
        host.settle()
        #expect(try host.highlight(.keyOpacity) == 0)
        #expect(try host.highlight("keyAmount") == 0.5)
        #expect(try host.highlight("keyHeight") == 0.05)
        host.model.style = .native
        host.settle()
        #expect(try host.highlight("keyAmount") == 0.5, "back to the system's own rim")
        #expect(try host.highlight("keyHeight") == 1)
    }
}

extension GlassHost {
    func rimLayer() throws -> CALayer {
        guard let root = view.layer, let layer = TunedGlassView.highlightLayers(in: root).first else { throw NotFound(what: "rim layer") }
        return layer
    }

    func rimOpacity() throws -> Float { try rimLayer().opacity }

    func highlight(_ key: String) throws -> Double? {
        (TunedGlassView.highlightEffect(of: try rimLayer())?.value(forKey: key) as? NSNumber)?.doubleValue
    }

    func highlight(_ property: GlassHighlight.Property) throws -> Double? {
        TunedGlassView.highlightEffect(of: try rimLayer()).flatMap { TunedGlassView.highlightValue(property, of: $0) }
    }

    /// The rim of the plain `.clear` glass the probe can show beside DockGlass.
    func plainGlassRimOpacity() -> Float? {
        guard let root = window.contentView?.layer else { return nil }
        let ours = view.layer.map(TunedGlassView.highlightLayers(in:)) ?? []
        return TunedGlassView.highlightLayers(in: root).first { layer in !ours.contains { $0 === layer } }?.opacity
    }
}
