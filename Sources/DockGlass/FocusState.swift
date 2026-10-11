import Darwin
import DockGlassShims
import SwiftUI

extension DockGlassStyle {
    /// Which window state the glass draws in.
    ///
    /// macOS draws Liquid Glass differently in an inactive window: it hides the glass's specular
    /// rim and blurs and frosts the face. The native switcher always draws active, even though the
    /// Dock never becomes the active app, so by default DockGlass draws in the state its look was
    /// fitted in, whatever the host window's state. That is what makes glass in a non-activating
    /// panel (a switcher overlay) and in a key window (a settings preview) look the same.
    public enum FocusState: Sendable, Equatable {
        /// Draw in the state the running system's look was fitted in, whatever the host window's
        /// state: active on macOS 27, where the native switcher's glass is drawn active. The
        /// default.
        case native
        /// Always draw as in an active window.
        case active
        /// Always draw as in an inactive window.
        case inactive
        /// Follow the host window, like any other glass: active while it is key or main in the
        /// active app, inactive otherwise.
        case matchWindow
    }
}

/// SwiftUICore, which exports the private symbols below. It loads lazily, so look it up by path:
/// `dlsym` on a handle that has not loaded it returns nil even where the symbol exists.
nonisolated(unsafe) private let swiftUICore = dlopen("/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore", RTLD_NOW)

/// Drives SwiftUI's internal `EnvironmentValues.windowAppearsActive`, which glass reads to choose
/// between its active and inactive rendering.
///
/// The public `appearsActive`, `controlActiveState` and `materialActiveAppearance` values do not
/// reach glass on macOS 27; only the window's `_hasActiveAppearanceIgnoringKeyFocus` does, and
/// SwiftUI copies that into this key when it builds a hosting view's environment. Setting the key
/// below that point changes only DockGlass's own subtree, so the host window keeps its own state.
///
/// The accessor is looked up at run time and validated before first use; when it is missing or
/// does not behave like a `Bool` property, `isAvailable` is false and the glass follows the window.
enum WindowActiveOverride {
    nonisolated(unsafe) private static let symbols: (setter: UnsafeMutableRawPointer, getter: UnsafeMutableRawPointer)? = {
        guard let handle = swiftUICore,
              let setter = dlsym(handle, "$s7SwiftUI17EnvironmentValuesV19windowAppearsActiveSbvs"),
              let getter = dlsym(handle, "$s7SwiftUI17EnvironmentValuesV19windowAppearsActiveSbvg")
        else { return nil }
        return (setter, getter)
    }()

    /// Whether the override works on this system: both accessors exist and round-trip a value.
    static let isAvailable: Bool = {
        guard let symbols else { return false }
        var environment = EnvironmentValues()
        return withUnsafeMutablePointer(to: &environment) { pointer in
            dockglass_call_bool_setter(symbols.setter, true, pointer)
            let afterTrue = dockglass_call_bool_getter(symbols.getter, pointer)
            dockglass_call_bool_setter(symbols.setter, false, pointer)
            let afterFalse = dockglass_call_bool_getter(symbols.getter, pointer)
            return afterTrue && !afterFalse
        }
    }()

    static func set(_ active: Bool, in environment: inout EnvironmentValues) {
        guard isAvailable, let symbols else { return }
        withUnsafeMutablePointer(to: &environment) { pointer in
            dockglass_call_bool_setter(symbols.setter, active, pointer)
        }
    }
}

extension View {
    /// Draws the glass inside in the given focus state, or leaves the window's state in place.
    /// Resolve `.native` against the look first.
    @ViewBuilder
    func dockGlassFocusState(_ state: DockGlassStyle.FocusState) -> some View {
        switch state {
        case .matchWindow, .native: self
        case .active: transformEnvironment(\.self) { WindowActiveOverride.set(true, in: &$0) }
        case .inactive: transformEnvironment(\.self) { WindowActiveOverride.set(false, in: &$0) }
        }
    }
}

/// SwiftUI's private Dock glass, `_Glass.dock`, which the native switcher's material matches.
///
/// Public `Glass` is a single-field wrapper around `_Glass`, so the private getter's result is a
/// valid `Glass`. The getter is looked up at run time rather than bound by symbol name, so a
/// macOS without it falls back to `.clear` instead of failing to launch.
enum DockVariant {
    static let glass: Glass? = {
        guard let handle = swiftUICore,
              let getter = dlsym(handle, "$s7SwiftUI6_GlassV4dockACvgZ")
        else { return nil }
        let result = UnsafeMutablePointer<Glass>.allocate(capacity: 1)
        defer { result.deallocate() }
        dockglass_call_indirect_static_getter(getter, result)
        return result.move()
    }()
}
