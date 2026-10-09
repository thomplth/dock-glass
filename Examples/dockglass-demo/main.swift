import AppKit
import SwiftUI
import DockGlass

// Shows DockGlass over a busy backdrop: a switcher cartouche with stock Apple apps, and a plate
// with a SwiftUI shadow, as apps such as Debut use it.
//
//   dockglass-demo [--capture <file.png>]
//
// With --capture, the window is captured after it settles and the demo exits.

setvbuf(stdout, nil, _IONBF, 0)
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let arguments = CommandLine.arguments
let capturePath = arguments.firstIndex(of: "--capture").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }

let stockApps = ["com.apple.finder", "com.apple.Safari", "com.apple.mail", "com.apple.Notes", "com.apple.iCal", "com.apple.Music", "com.apple.Preview", "com.apple.systempreferences"]
let icons: [(NSImage, String)] = stockApps.compactMap { id in
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
    return (NSWorkspace.shared.icon(forFile: url.path), FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
}

struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.orange, .pink, .purple, .blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                ForEach(0..<40) { i in
                    Rectangle().fill(i.isMultiple(of: 2) ? Color.black.opacity(0.5) : Color.white.opacity(0.35)).frame(width: 18)
                    Spacer(minLength: 18)
                }
            }
            .rotationEffect(.degrees(18)).scaleEffect(1.5)
        }
    }
}

struct Demo: View {
    var body: some View {
        ZStack {
            Backdrop()
            VStack(spacing: 48) {
                Cartouche {
                    HStack(alignment: .top, spacing: DockGlass.Metrics.standard.iconSpacing) {
                        ForEach(Array(icons.enumerated()), id: \.offset) { index, item in
                            CartoucheIcon(item.0, label: item.1, isSelected: index == 1)
                        }
                    }
                }
                Color.clear
                    .frame(width: 420, height: 180)
                    .dockGlass(in: RoundedRectangle(cornerRadius: 30))
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                    .overlay(Text("Plate with a SwiftUI shadow").font(.title2.bold()))
            }
        }
        .frame(width: 1400, height: 640)
    }
}

let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 640), styleMask: [.titled, .closable], backing: .buffered, defer: false)
window.title = "DockGlass"
window.contentView = NSHostingView(rootView: Demo())
window.center()
window.makeKeyAndOrderFront(nil)
app.activate(ignoringOtherApps: true)

if let capturePath {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l\(window.windowNumber)", capturePath]
        try? process.run()
        process.waitUntilExit()
        print("status:", DockGlass.status)
        exit(0)
    }
}
app.run()
