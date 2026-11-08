import SwiftUI
import IOKit.hid
import ServiceManagement

struct Effect: Identifiable {
    let id: UInt8
    let name: String
    let symbol: String
    var hasDirection = false
    var hasColor = true
    var hasSpeed = true

    static let all: [Effect] = [
        Effect(id: 0x01, name: "Wave", symbol: "water.waves", hasDirection: true),
        Effect(id: 0x02, name: "Long Wave", symbol: "wind", hasDirection: true),
        Effect(id: 0x12, name: "Ring Wave", symbol: "circle.circle", hasDirection: true),
        Effect(id: 0x0C, name: "Rain", symbol: "cloud.rain", hasDirection: true),
        Effect(id: 0x03, name: "Swirl", symbol: "tornado", hasDirection: true),
        Effect(id: 0x04, name: "Cycle", symbol: "rainbow"),
        Effect(id: 0x05, name: "Breathing", symbol: "lungs"),
        Effect(id: 0x06, name: "Static", symbol: "lightbulb", hasSpeed: false),
        Effect(id: 0x10, name: "Visor", symbol: "arrow.left.and.right", hasDirection: true),
        Effect(id: 0x0B, name: "Blooming", symbol: "camera.macro"),
        Effect(id: 0x0A, name: "Starlight", symbol: "sparkles"),
        Effect(id: 0x0F, name: "Twinkle", symbol: "star"),
        Effect(id: 0x07, name: "Reactive", symbol: "hand.tap"),
        Effect(id: 0x08, name: "Ripple", symbol: "dot.radiowaves.left.and.right"),
        Effect(id: 0x09, name: "Streak", symbol: "line.3.horizontal"),
        Effect(id: 0x0D, name: "Hurricane", symbol: "hurricane"),
        Effect(id: 0x0E, name: "Accumulate", symbol: "square.stack.3d.up"),
        Effect(id: 0x11, name: "Surmount", symbol: "mountain.2"),
        Effect(id: 0x14, name: "Custom", symbol: "square.grid.3x3", hasColor: false, hasSpeed: false),
    ]

    static func named(_ id: UInt8) -> Effect? { all.first { $0.id == id } }
}

struct Preset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var state: LightingState
    var builtIn = false

    static let builtIns: [Preset] = [
        Preset(name: "Rainbow Wave", state: .init(mode: 0x01, speed: 3, random: true), builtIn: true),
        Preset(name: "Ocean", state: .init(mode: 0x02, speed: 4, random: false, r: 0, g: 120, b: 255), builtIn: true),
        Preset(name: "Neon Ring", state: .init(mode: 0x12, speed: 2, random: true), builtIn: true),
        Preset(name: "Ember", state: .init(mode: 0x05, speed: 3, random: false, r: 255, g: 60, b: 0), builtIn: true),
        Preset(name: "Matrix", state: .init(mode: 0x0C, speed: 2, random: false, r: 0, g: 255, b: 60), builtIn: true),
        Preset(name: "Clean White", state: .init(mode: 0x06, random: false, r: 255, g: 251, b: 240), builtIn: true),
    ]
}

@MainActor
final class KeyboardController: ObservableObject {
    enum Status: Equatable { case searching, connected, needsPermission, error(String) }

    @Published private(set) var state = LightingState()
    @Published private(set) var status: Status = .searching
    @Published private(set) var userPresets: [Preset] = []
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let device = GMMKDevice()
    private var lastBrightness: UInt8 = 4
    private let presetsKey = "userPresets"

    var isConnected: Bool { status == .connected }
    var isOn: Bool { state.brightness > 0 }
    var currentEffect: Effect? { Effect.named(state.mode) }

    init() {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let saved = try? JSONDecoder().decode([Preset].self, from: data) {
            userPresets = saved
        }
        device.onConnectionChange = { [weak self] connected in
            guard let self else { return }
            self.status = connected ? .connected : .searching
            if connected { self.refresh() }
        }
        device.onPermissionDenied = { [weak self] in self?.status = .needsPermission }
        device.start()
    }

    func refresh() {
        device.readState { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let s):
                self.state = s
                if s.brightness > 0 { self.lastBrightness = s.brightness }
                self.status = .connected
            case .failure(let e):
                self.status = .error(e.localizedDescription)
            }
        }
    }

    func update(_ change: (inout LightingState) -> Void) {
        var s = state
        change(&s)
        guard s != state else { return }
        state = s
        if s.brightness > 0 { lastBrightness = s.brightness }
        device.apply(s) { [weak self] error in
            if let error { self?.status = .error(error.localizedDescription) }
            else if self?.status != .connected { self?.status = .connected }
        }
    }

    func binding<T>(_ keyPath: WritableKeyPath<LightingState, T>) -> Binding<T> {
        Binding(get: { self.state[keyPath: keyPath] }, set: { v in self.update { $0[keyPath: keyPath] = v } })
    }

    func togglePower() {
        update { $0.brightness = $0.brightness > 0 ? 0 : max(lastBrightness, 1) }
    }

    func setColor(_ color: Color) {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return }
        update {
            $0.random = false
            $0.r = UInt8(max(0, min(255, (c.redComponent * 255).rounded())))
            $0.g = UInt8(max(0, min(255, (c.greenComponent * 255).rounded())))
            $0.b = UInt8(max(0, min(255, (c.blueComponent * 255).rounded())))
        }
    }

    var color: Color {
        Color(.sRGB, red: Double(state.r) / 255, green: Double(state.g) / 255, blue: Double(state.b) / 255)
    }

    // MARK: Presets

    func apply(_ preset: Preset) {
        update { s in
            let keepBrightness = s.brightness
            s = preset.state
            s.brightness = keepBrightness > 0 ? keepBrightness : max(lastBrightness, 1)
        }
    }

    func saveCurrent(as name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        userPresets.append(Preset(name: trimmed.isEmpty ? "Preset \(userPresets.count + 1)" : trimmed, state: state))
        persistPresets()
    }

    func delete(_ preset: Preset) {
        userPresets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(userPresets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }

    // MARK: System

    func requestPermission() {
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            status = .error("Login item: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
