import AppKit
import SwiftUI

/// Renders the real menu UI with sample state into PNGs (for the README). No USB access.
@MainActor
enum Screenshots {
    static func render(to dir: URL) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let saved = [Preset(name: "Late Night", state: .init(mode: 0x05, speed: 4, random: false, r: 140, g: 0, b: 255))]
        let shots: [(String, LightingState, NSAppearance.Name)] = [
            ("screenshot-dark", .init(mode: 0x01, brightness: 4, speed: 3, direction: 0, random: true), .darkAqua),
            ("screenshot-light", .init(mode: 0x02, brightness: 3, speed: 4, direction: 1, random: false, r: 0, g: 120, b: 255), .aqua),
            ("screenshot-breathing", .init(mode: 0x05, brightness: 4, speed: 2, random: false, r: 255, g: 60, b: 0), .darkAqua),
        ]
        for (name, state, appearance) in shots {
            let kb = KeyboardController(preview: state, presets: saved)
            snapshot(kb: kb, appearance: appearance, to: dir.appendingPathComponent("\(name).png"))
        }
    }

    private static func snapshot(kb: KeyboardController, appearance: NSAppearance.Name, to url: URL) {
        let root = ContentView()
            .environmentObject(kb)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
            .padding(36)

        let host = NSHostingView(rootView: root)
        host.appearance = NSAppearance(named: appearance)
        host.frame = CGRect(origin: .zero, size: host.fittingSize)

        let window = KeyWindow(contentRect: host.frame.offsetBy(dx: -20000, dy: -20000),
                               styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print("wrote \(url.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
        }
        window.close()
    }
}

/// Borderless windows can't become key by default; key state makes controls render "active".
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
