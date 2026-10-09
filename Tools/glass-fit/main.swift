import AppKit
import SwiftUI
@_spi(Fitting) import DockGlass

// glass-fit: captures the native Cmd-Tab switcher and fits DockGlass tuning tables against it.
//
//   glass-fit capture <dir> [--keep-rejected]
//       Captures each backdrop alone, then the native switcher over it. Quit any app that
//       replaces Cmd-Tab first. A capture where anything but the switcher differs from the
//       backdrop is deleted unseen, since it would contain whatever window intruded.
//   glass-fit fit <dir> --apps self,<bundle id>,... [--max-evals N] [--keep] [--tint-response] [--any-system]
//       --any-system tunes even on a macOS version without verified tables, to measure it.
//   glass-fit inspect
//       Prints the system glass filter's inputs and stock values for clear glass in light and dark
//       mode, which inputs DockGlass needs that are missing, and DockGlass's status.
//       Renders DockGlass's Cartouche over the same backdrops and searches the glass inputs and
//       rim for the lowest mean absolute error against the native captures. `--apps` lists the
//       switcher's apps in the order the native capture shows them; `self` is this tool, which is
//       frontmost when the switcher opens.
//
// Both modes take over the screen for their duration and need Screen Recording and
// Accessibility (to post Cmd-Tab) for the process that launches them.

setvbuf(stdout, nil, _IONBF, 0)
let arguments = CommandLine.arguments
guard arguments.count >= 2, ["capture", "fit", "inspect"].contains(arguments[1]),
      arguments[1] == "inspect" || arguments.count >= 3 else {
    print("usage: glass-fit capture <dir> | glass-fit fit <dir> --apps self,<bundle id>,... | glass-fit inspect")
    exit(2)
}
let mode = arguments[1]
let dir = mode == "inspect" ? NSTemporaryDirectory() : arguments[2]
try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
func option(_ name: String) -> String? {
    arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let metrics = DockGlass.Metrics.standard
let backdropNames = ["A", "B"]

// MARK: - Backdrops

/// Saturated diagonal stripes under heavy text: hue, tone and refraction all vary.
struct BackdropA: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.orange, .pink, .purple, .blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                ForEach(0..<36) { i in
                    Rectangle().fill(i.isMultiple(of: 2) ? Color.black.opacity(0.55) : Color.white.opacity(0.35)).frame(width: 20)
                    Spacer(minLength: 20)
                }
            }
            .rotationEffect(.degrees(18)).scaleEffect(1.6)
            VStack(spacing: 18) {
                ForEach(0..<12) { _ in
                    Text("The quick brown fox jumps over the lazy dog 0123456789")
                        .font(.system(size: 34, weight: .heavy)).foregroundStyle(.black.opacity(0.75))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// A dark-to-light ramp with saturated discs and a fine grid that shows refraction directly.
struct BackdropB: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.05), Color(white: 0.5), Color(white: 0.95)], startPoint: .leading, endPoint: .trailing)
            ForEach(0..<9) { i in
                Circle().fill([Color.green, .yellow, .cyan, .red, .indigo, .mint, .orange, .purple, .blue][i])
                    .frame(width: 520, height: 520)
                    .offset(x: CGFloat(i) * 300 - 1200, y: i.isMultiple(of: 2) ? -140 : 160)
                    .opacity(0.85)
            }
            Path { p in
                for x in stride(from: 0, through: 2600, by: 48) { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: 1500)) }
                for y in stride(from: 0, through: 1500, by: 36) { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: 2600, y: y)) }
            }
            .stroke(Color.black.opacity(0.6), lineWidth: 3)
        }
        .ignoresSafeArea()
    }
}

let screen = NSScreen.main!.frame
let backdrop = NSWindow(contentRect: screen, styleMask: [.borderless], backing: .buffered, defer: false)
// Above ordinary windows so nothing else can intrude into a capture.
backdrop.level = .floating
func showBackdrop(_ name: String) {
    backdrop.contentView = NSHostingView(rootView: name == "A" ? AnyView(BackdropA()) : AnyView(BackdropB()))
}
/// The capture region: wide enough for 16 apps where the screen allows, centred where the
/// switcher opens.
let regionWidth = min(2300, screen.width)
let region = NSRect(x: screen.midX - regionWidth / 2, y: screen.midY - 150, width: regionWidth, height: 300)

func capture(_ name: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-R\(Int(region.minX)),\(Int(screen.maxY - region.maxY)),\(Int(region.width)),\(Int(region.height))", "\(dir)/\(name).png"]
    try? process.run()
    process.waitUntilExit()
}

struct Bitmap {
    let width: Int, height: Int
    let pixels: [UInt8]

    init?(path: String) {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        width = image.width
        height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        pixels = buffer
    }
}

func key(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
    let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
    event.flags = flags
    event.post(tap: .cghidEventTap)
}

// MARK: - Inspect

if mode == "inspect" {
    print("system:", ProcessInfo.processInfo.operatingSystemVersionString)
    print("glass tint amount:", UserDefaults.standard.double(forKey: "NSGlassTintAmount"))
    struct Probe: View {
        var body: some View {
            Text("probe").frame(width: 300, height: 160).dockGlass(in: RoundedRectangle(cornerRadius: 40, style: .continuous))
        }
    }
    func backdropLayers(_ layer: CALayer) -> [CALayer] {
        (NSStringFromClass(type(of: layer)) == "CABackdropLayer" ? [layer] : []) + (layer.sublayers ?? []).flatMap(backdropLayers)
    }
    for appearance in [NSAppearance.Name.aqua, .darkAqua] {
        // Stock values: inspect with tuning disabled so the filter shows the system's own inputs.
        DockGlass.isEnabled = false
        let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 300, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSAppearance(named: appearance)
        window.contentView = NSHostingView(rootView: Probe())
        window.orderFrontRegardless()
        window.displayIfNeeded()
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let layers = window.contentView?.layer.map(backdropLayers) ?? []
        print("\n== \(appearance == .aqua ? "light" : "dark"): \(layers.count) backdrop layer(s)")
        guard let layer = layers.first,
              let filter = (layer.filters as? [NSObject])?.first(where: { ($0.value(forKey: "name") as? String) == "glassBackground" }) else {
            print("no glassBackground filter")
            continue
        }
        let keys = Set(filter.value(forKey: "inputKeys") as? [String] ?? [])
        let needed = GlassTuning.Input.allCases.map(\.rawValue) + ["inputBlurFillNormalOpacity", "inputBlurFillBlurRadius"]
        print("filter inputs:", keys.count, "  missing for DockGlass:", needed.filter { !keys.contains($0) })
        for key in needed where keys.contains(key) {
            print("  \(key) = \(filter.value(forKey: key) ?? "nil")")
        }
        print("  backdrop scale = \(layer.value(forKey: "scale") ?? "nil")")
        DockGlass.isEnabled = true
        window.displayIfNeeded()
        CATransaction.flush()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        print("DockGlass status:", DockGlass.status)
        window.orderOut(nil)
    }
    exit(0)
}

// MARK: - Capture

if mode == "capture" {
    var index = 0
    func next() {
        guard index < backdropNames.count else {
            let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let meta: [String: Any] = [
                "appearance": isDark ? "dark" : "light",
                "glassTintAmount": UserDefaults.standard.object(forKey: "NSGlassTintAmount") ?? 0,
                "system": ProcessInfo.processInfo.operatingSystemVersionString,
                "screen": "\(Int(screen.width))x\(Int(screen.height))@\(NSScreen.main!.backingScaleFactor)x",
            ]
            let data = try! JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted, .sortedKeys])
            try! data.write(to: URL(fileURLWithPath: "\(dir)/meta.json"))
            print("captured into \(dir): \(String(data: data, encoding: .utf8)!)")
            exit(0)
        }
        let name = backdropNames[index]
        index += 1
        showBackdrop(name)
        backdrop.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            capture("backdrop\(name)")
            app.activate(ignoringOtherApps: true)
            backdrop.makeKeyAndOrderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                key(55, true, .maskCommand); key(48, true, .maskCommand); key(48, false, .maskCommand)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    capture("native\(name)")
                    key(53, true, .maskCommand); key(53, false, .maskCommand); key(55, false, [])
                    rejectIntrusions(name)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { next() }
                }
            }
        }
    }
    /// Deletes a native capture whose rows above and below the switcher differ from the backdrop.
    func rejectIntrusions(_ name: String) {
        let path = "\(dir)/native\(name).png"
        guard let native = Bitmap(path: path), let back = Bitmap(path: "\(dir)/backdrop\(name).png"), native.width == back.width else {
            try? FileManager.default.removeItem(atPath: path)
            print("native\(name): unreadable, deleted")
            return
        }
        let band = native.height * 3 / 20
        var mismatched = 0
        for y in Array(0..<band) + Array((native.height - band)..<native.height) {
            for x in 0..<native.width {
                let i = (y * native.width + x) * 4
                if (0..<3).contains(where: { abs(Int(native.pixels[i + $0]) - Int(back.pixels[i + $0])) > 3 }) { mismatched += 1 }
            }
        }
        if mismatched > 200 {
            if arguments.contains("--keep-rejected") {
                // Only for disposable machines, where an intruding window cannot be private.
                try? FileManager.default.moveItem(atPath: path, toPath: "\(dir)/native\(name).rejected.png")
                print("native\(name): \(mismatched) pixels outside the switcher differ from the backdrop; kept as rejected")
            } else {
                try? FileManager.default.removeItem(atPath: path)
                print("native\(name): \(mismatched) pixels outside the switcher differ from the backdrop; deleted unseen")
            }
        } else {
            print("native\(name): clean")
        }
    }
    next()
    app.run()
}

// MARK: - Fit

guard let appList = option("--apps")?.split(separator: ",").map(String.init) else {
    print("fit needs --apps self,<bundle id>,... in the native capture's order")
    exit(2)
}
let maxEvals = option("--max-evals").flatMap(Int.init) ?? 200
let running = NSWorkspace.shared.runningApplications
let items: [(image: NSImage, name: String)] = appList.compactMap { id in
    let match = id == "self" ? NSRunningApplication.current : running.first { $0.bundleIdentifier == id }
    guard let match, let icon = match.icon else { print("not running: \(id)"); return nil }
    return (icon, id == "self" ? "exec" : (match.localizedName ?? id))
}
let natives: [(name: String, bitmap: Bitmap)] = backdropNames.compactMap { name in
    Bitmap(path: "\(dir)/native\(name).png").map { (name, $0) }
}
guard !natives.isEmpty else { print("no native captures in \(dir)"); exit(1) }
let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
if arguments.contains("--any-system") {
    DockGlass.fittingAdoptLook(forMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
}

struct Replica: View {
    var body: some View {
        Cartouche(metrics: metrics) {
            HStack(alignment: .top, spacing: metrics.iconSpacing) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    CartoucheIcon(item.image, label: item.name, isSelected: index == 1, metrics: metrics)
                }
            }
        }
    }
}

let plateWidth = metrics.plateWidth(iconCount: items.count)
let plateRect = NSRect(x: screen.midX - plateWidth / 2, y: screen.midY - metrics.plateHeight / 2, width: plateWidth, height: metrics.plateHeight)
let panel = NSPanel(contentRect: plateRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.level = .statusBar
panel.contentView = NSHostingView(rootView: Replica())

// Score the plate plus a small margin, so rims and outer edges count.
let reference = natives[0].bitmap
let scale = NSScreen.main!.backingScaleFactor
var mask = [Bool](repeating: false, count: reference.width * reference.height)
for y in 0..<reference.height {
    for x in 0..<reference.width {
        let px = CGFloat(x) / scale - (plateRect.minX - region.minX)
        let py = CGFloat(y) / scale - (region.maxY - plateRect.maxY)
        mask[y * reference.width + x] = px >= -6 && py >= -6 && px < plateWidth + 6 && py < metrics.plateHeight + 6
    }
}
func error(_ candidate: Bitmap, _ native: Bitmap) -> Double {
    var total = 0.0, count = 0
    for i in 0..<(native.width * native.height) where mask[i] {
        for c in 0..<3 { total += abs(Double(candidate.pixels[i * 4 + c]) - Double(native.pixels[i * 4 + c])) }
        count += 3
    }
    return total / Double(count)
}

struct Parameter {
    let name: String
    var value: Double
    var step: Double
    let range: ClosedRange<Double>
}
let start = (isDark ? DockGlass.fittingTables.dark : DockGlass.fittingTables.light) ?? GlassTuning.light
let steps: [GlassTuning.Input: (Double, ClosedRange<Double>)] = [
    .blurRadius: (1, 0...10), .innerRefractionHeight: (2, 2...40), .innerRefractionAmount: (10, -160...0),
    .faceColorBlack: (0.03, 0...0.5), .faceColorWhite: (0.03, 0.6...1.1), .faceColorSaturation: (0.08, 0.6...2),
    .faceColorMaxLuma: (0.05, 0.3...1), .faceColorMaxLumaSDR: (0.05, 0.3...1),
]
var parameters = GlassTuning.Input.allCases.map { input in
    Parameter(name: input.rawValue, value: start.values[input] ?? 0, step: steps[input]!.0, range: steps[input]!.1)
}
let startRim = isDark ? DockGlass.fittingRims.dark : DockGlass.fittingRims.light
let startSelection = isDark ? DockGlass.fittingSelection.dark : DockGlass.fittingSelection.light
parameters.append(Parameter(name: "rimOpacity", value: startRim.opacity, step: 0.1, range: 0...0.8))
parameters.append(Parameter(name: "rimWidth", value: Double(startRim.width), step: 0.25, range: 0.25...3))
parameters.append(Parameter(name: "selectionGray", value: startSelection.gray, step: 0.06, range: 0...1))
// --tint-response fits only how the fill follows the tint slider, holding the appearance tuning,
// rim and selection at their current values. Capture at a tint between 0 and 1 for this.
let fitsTintResponse = arguments.contains("--tint-response")
let startResponse = isDark ? DockGlass.fittingTintResponses.dark : DockGlass.fittingTintResponses.light
if fitsTintResponse {
    parameters.append(Parameter(name: "halfwayFillOpacity", value: startResponse.halfwayFillOpacity, step: 0.1, range: 0...1))
    parameters.append(Parameter(name: "halfwayFillBlurRadius", value: startResponse.halfwayFillBlurRadius, step: 2, range: 0...24))
}
let fittedNames: Set<String> = fitsTintResponse ? ["halfwayFillOpacity", "halfwayFillBlurRadius"] : Set(parameters.map(\.name))

func applyParameters() {
    var values: [GlassTuning.Input: Double] = [:]
    for input in GlassTuning.Input.allCases { values[input] = parameters.first { $0.name == input.rawValue }!.value }
    let tuning = GlassTuning(values)
    DockGlass.fittingTables = isDark ? (DockGlass.fittingTables.light, tuning) : (tuning, DockGlass.fittingTables.dark)
    let rim = GlassRim(
        opacity: parameters.first { $0.name == "rimOpacity" }!.value,
        width: parameters.first { $0.name == "rimWidth" }!.value
    )
    DockGlass.fittingRims = isDark ? (DockGlass.fittingRims.light, rim) : (rim, DockGlass.fittingRims.dark)
    let selection = SelectionStyle(blend: startSelection.blend, gray: parameters.first { $0.name == "selectionGray" }!.value)
    if fitsTintResponse {
        let response = TintResponse(
            halfwayFillOpacity: parameters.first { $0.name == "halfwayFillOpacity" }!.value,
            halfwayFillBlurRadius: parameters.first { $0.name == "halfwayFillBlurRadius" }!.value
        )
        DockGlass.fittingTintResponses = isDark ? (DockGlass.fittingTintResponses.light, response) : (response, DockGlass.fittingTintResponses.dark)
    }
    let current = isDark ? DockGlass.fittingSelection.dark : DockGlass.fittingSelection.light
    if selection != current {
        DockGlass.fittingSelection = isDark ? (DockGlass.fittingSelection.light, selection) : (selection, DockGlass.fittingSelection.dark)
        // The highlight reads its style when SwiftUI renders it, so re-render the replica.
        panel.contentView = NSHostingView(rootView: Replica())
    }
}

var evaluations = 0
func evaluate(_ done: @escaping (Double) -> Void) {
    var scores: [Double] = []
    func run(_ i: Int) {
        guard i < natives.count else {
            evaluations += 1
            done(scores.reduce(0, +) / Double(scores.count))
            return
        }
        showBackdrop(natives[i].name)
        applyParameters()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            capture("eval\(natives[i].name)")
            if let candidate = Bitmap(path: "\(dir)/eval\(natives[i].name).png"), candidate.width == natives[i].bitmap.width {
                scores.append(error(candidate, natives[i].bitmap))
            } else {
                scores.append(999)
            }
            run(i + 1)
        }
    }
    run(0)
}

var best = Double.infinity
var index = 0, direction = 1.0, improved = false, passes = 0
/// Inputs the running glass filter has; parameters for inputs it lacks are not fitted.
var availableInputs: Set<String> = []
func discoverInputs() {
    func backdropLayers(_ layer: CALayer) -> [CALayer] {
        (NSStringFromClass(type(of: layer)) == "CABackdropLayer" ? [layer] : []) + (layer.sublayers ?? []).flatMap(backdropLayers)
    }
    guard let layer = panel.contentView?.layer.map(backdropLayers)?.first,
          let filter = (layer.filters as? [NSObject])?.first(where: { ($0.value(forKey: "name") as? String) == "glassBackground" }) else { return }
    availableInputs = Set(filter.value(forKey: "inputKeys") as? [String] ?? [])
    let skipped = parameters.map(\.name).filter { $0.hasPrefix("input") && !availableInputs.contains($0) }
    if !skipped.isEmpty { print("not in this system's filter, not fitted:", skipped.joined(separator: ", ")) }
}
func isFittable(_ name: String) -> Bool {
    fittedNames.contains(name) && (!name.hasPrefix("input") || availableInputs.contains(name))
}
func step() {
    if evaluations >= maxEvals || passes >= 4 { finish(); return }
    if index >= parameters.count {
        index = 0
        passes += 1
        if !improved { for i in parameters.indices { parameters[i].step /= 2 } }
        improved = false
    }
    guard isFittable(parameters[index].name) else { index += 1; direction = 1; step(); return }
    let old = parameters[index].value
    let candidate = min(parameters[index].range.upperBound, max(parameters[index].range.lowerBound, old + direction * parameters[index].step))
    if candidate == old { advance(); return }
    parameters[index].value = candidate
    evaluate { score in
        if score < best - 0.01 {
            best = score
            improved = true
            print(String(format: "eval %3d  error %.3f  %@ = %.4g", evaluations, score, parameters[index].name, candidate))
            step()
        } else {
            parameters[index].value = old
            advance()
        }
    }
}
func advance() {
    if direction > 0 { direction = -1 } else { direction = 1; index += 1 }
    step()
}
func finish() {
    applyParameters()
    if !arguments.contains("--keep") {
        for name in backdropNames { try? FileManager.default.removeItem(atPath: "\(dir)/eval\(name).png") }
    }
    func value(_ name: String) -> String { String(format: "%.4g", parameters.first { $0.name == name }!.value) }
    print(String(format: "\nbest mean absolute error %.3f/255 after %d evaluations (%@ appearance)\n", best, evaluations, isDark ? "dark" : "light"))
    print("GlassTuning([")
    for input in GlassTuning.Input.allCases { print("    .\(input): \(value(input.rawValue)),") }
    print("])")
    print("GlassRim(opacity: \(value("rimOpacity")), width: \(value("rimWidth")))")
    print("SelectionStyle(blend: .\(startSelection.blend), gray: \(value("selectionGray")))")
    if fitsTintResponse {
        print("TintResponse(halfwayFillOpacity: \(value("halfwayFillOpacity")), halfwayFillBlurRadius: \(value("halfwayFillBlurRadius")))")
    }
    exit(0)
}

showBackdrop(natives[0].name)
backdrop.orderFrontRegardless()
panel.orderFrontRegardless()
DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    evaluate { score in
        best = score
        print(String(format: "start error %.3f", score))
        discoverInputs()
        step()
    }
}
app.run()
