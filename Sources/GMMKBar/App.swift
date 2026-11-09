import SwiftUI
import Combine

@main
struct GMMKBarApp: App {
    @NSApplicationDelegateAdaptor(StatusBarController.self) private var statusBar

    init() {
        // `GMMKBar --screenshots <dir>` renders README screenshots offline and exits.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--screenshots"), i + 1 < args.count {
            MainActor.assumeIsolated { Screenshots.render(to: URL(fileURLWithPath: args[i + 1])) }
            exit(0)
        }
    }

    // The menu bar item is managed in AppKit (see StatusBarController); this scene is never shown.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Owns a fixed square-width NSStatusItem and a popover hosting the SwiftUI panel.
/// (SwiftUI's MenuBarExtra sized its item wider than a single icon slot.)
@MainActor
final class StatusBarController: NSObject, NSApplicationDelegate {
    private let keyboard = KeyboardController()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: ContentView().environmentObject(keyboard))

        updateIcon()
        // objectWillChange fires before the value changes; hop to the next runloop turn to read the new state.
        cancellable = keyboard.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
    }

    private func updateIcon() {
        let name = keyboard.isConnected && keyboard.isOn ? "keyboard.fill" : "keyboard"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "GMMK Lights")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var kb: KeyboardController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Header()
            switch kb.status {
            case .connected, .error:
                if case .error(let msg) = kb.status { Banner(text: msg, symbol: "exclamationmark.triangle") }
                EffectGrid()
                Divider()
                Controls()
                Divider()
                Presets()
            case .searching:
                Banner(text: "Plug in your GMMK keyboard…", symbol: "cable.connector")
            case .needsPermission:
                VStack(alignment: .leading, spacing: 8) {
                    Banner(text: "macOS needs Input Monitoring permission to talk to the keyboard.",
                           symbol: "lock.shield")
                    Button("Open Privacy Settings") { kb.requestPermission() }
                    Text("Enable “GMMK Lights”, then quit and reopen the app.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Footer()
        }
        .padding(14)
        .frame(width: 340)
    }
}

// MARK: - Header

struct Header: View {
    @EnvironmentObject var kb: KeyboardController

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(kb.isOn && kb.isConnected ? AnyShapeStyle(rainbow) : AnyShapeStyle(.quaternary))
                    .frame(width: 34, height: 34)
                Image(systemName: "keyboard").foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("GMMK TKL").font(.headline)
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if kb.isConnected {
                Toggle("", isOn: Binding(get: { kb.isOn }, set: { _ in kb.togglePower() }))
                    .toggleStyle(.switch).labelsHidden()
                    .help("Lights on/off")
            }
        }
    }

    private var statusText: String {
        switch kb.status {
        case .connected: return kb.isOn ? (kb.currentEffect?.name ?? "Connected") : "Lights off"
        case .searching: return "Not connected"
        case .needsPermission: return "Permission needed"
        case .error: return "Connected (with errors)"
        }
    }

    private var rainbow: AngularGradient {
        AngularGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)
    }
}

struct Banner: View {
    let text: String
    let symbol: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.callout)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Effects

struct EffectGrid: View {
    @EnvironmentObject var kb: KeyboardController
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Effect")
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Effect.all) { effect in
                    let selected = kb.state.mode == effect.id
                    Button {
                        kb.update { $0.mode = effect.id; if $0.brightness == 0 { $0.brightness = 4 } }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: effect.symbol).font(.system(size: 15)).frame(height: 18)
                            Text(effect.name).font(.system(size: 9.5)).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary.opacity(0.6)),
                                    in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(selected ? .white : .primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(effect.name)
                }
            }
        }
    }
}

// MARK: - Controls

struct Controls: View {
    @EnvironmentObject var kb: KeyboardController
    private let swatches: [Color] = [
        .init(red: 1, green: 0, blue: 0), .init(red: 1, green: 0.4, blue: 0), .init(red: 1, green: 0.85, blue: 0),
        .init(red: 0, green: 1, blue: 0.2), .init(red: 0, green: 0.9, blue: 1), .init(red: 0, green: 0.3, blue: 1),
        .init(red: 0.55, green: 0, blue: 1), .init(red: 1, green: 0, blue: 0.6), .init(red: 1, green: 1, blue: 1),
    ]

    var body: some View {
        let effect = kb.currentEffect
        VStack(alignment: .leading, spacing: 10) {
            SliderRow(title: "Brightness", low: "sun.min", high: "sun.max.fill",
                      value: Binding(get: { Double(kb.state.brightness) },
                                     set: { v in kb.update { $0.brightness = UInt8(v) } }),
                      range: 0...4)

            if effect?.hasSpeed ?? true {
                SliderRow(title: "Speed", low: "tortoise", high: "hare",
                          value: Binding(get: { Double(5 - Int(kb.state.speed)) },
                                         set: { v in kb.update { $0.speed = UInt8(5 - Int(v)) } }),
                          range: 0...5)
            }

            if effect?.hasDirection ?? false {
                HStack {
                    Text("Direction").font(.callout)
                    Spacer()
                    Picker("", selection: Binding(get: { kb.state.direction == 0 ? 0 : 1 },
                                                  set: { v in kb.update { $0.direction = UInt8(v) } })) {
                        Image(systemName: "arrow.right").tag(0)
                        Image(systemName: "arrow.left").tag(1)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 110)
                }
            }

            if effect?.hasColor ?? true {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Color").font(.callout)
                        Spacer()
                        Toggle("Rainbow", isOn: kb.binding(\.random)).toggleStyle(.switch).controlSize(.small)
                    }
                    HStack(spacing: 6) {
                        ForEach(swatches.indices, id: \.self) { i in
                            Button { kb.setColor(swatches[i]) } label: {
                                Circle().fill(swatches[i])
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                        ColorPicker("", selection: Binding(get: { kb.color }, set: { kb.setColor($0) }),
                                    supportsOpacity: false)
                            .labelsHidden()
                    }
                    .opacity(kb.state.random ? 0.45 : 1)
                }
            }
        }
    }
}

struct SliderRow: View {
    let title: String, low: String, high: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.callout)
                Spacer()
                Text("\(Int(value))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Image(systemName: low).foregroundStyle(.secondary).frame(width: 16)
                Slider(value: $value, in: range, step: 1)
                Image(systemName: high).foregroundStyle(.secondary).frame(width: 16)
            }
        }
    }
}

// MARK: - Presets

struct Presets: View {
    @EnvironmentObject var kb: KeyboardController
    @State private var naming = false
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle("Presets")
                Spacer()
                Button { naming.toggle() } label: { Image(systemName: naming ? "xmark" : "plus") }
                    .buttonStyle(.borderless)
                    .help("Save current lighting as a preset")
            }
            if naming {
                HStack {
                    TextField("Preset name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                    Button("Save", action: save).keyboardShortcut(.defaultAction)
                }
            }
            FlowLayout(spacing: 6) {
                ForEach(Preset.builtIns + kb.userPresets) { preset in
                    Button { kb.apply(preset) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(swatch(preset.state)).frame(width: 9, height: 9)
                            Text(preset.name).font(.caption)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.quaternary.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if !preset.builtIn { Button("Delete “\(preset.name)”", role: .destructive) { kb.delete(preset) } }
                    }
                }
            }
        }
    }

    private func save() {
        kb.saveCurrent(as: newName)
        newName = ""
        naming = false
    }

    private func swatch(_ s: LightingState) -> AnyShapeStyle {
        s.random
            ? AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
            : AnyShapeStyle(Color(.sRGB, red: Double(s.r) / 255, green: Double(s.g) / 255, blue: Double(s.b) / 255))
    }
}

// MARK: - Footer

struct Footer: View {
    @EnvironmentObject var kb: KeyboardController

    var body: some View {
        HStack {
            Toggle("Launch at login", isOn: Binding(get: { kb.launchAtLogin }, set: { kb.setLaunchAtLogin($0) }))
                .toggleStyle(.checkbox).font(.caption)
            Spacer()
            Button { kb.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Re-read settings from keyboard")
                .disabled(!kb.isConnected)
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderless).keyboardShortcut("q")
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }
}

/// Simple wrapping layout for preset chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty && rows[rows.count - 1].width + spacing + size.width > maxWidth {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
