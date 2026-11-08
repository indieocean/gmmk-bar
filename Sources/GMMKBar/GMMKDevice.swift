import Foundation
import IOKit
import IOKit.hid

/// Lighting parameters 0x00-0x07 of the GMMK1 (SONiX/EVision 0C45:652F) config block.
struct LightingState: Equatable, Codable {
    var mode: UInt8 = 0x01
    var brightness: UInt8 = 4
    var speed: UInt8 = 3        // 0 = fastest, 5 = slowest
    var direction: UInt8 = 0
    var random: Bool = true     // true = rainbow / multi-color
    var r: UInt8 = 255
    var g: UInt8 = 0
    var b: UInt8 = 0

    var bytes: [UInt8] { [mode, brightness, speed, direction, random ? 1 : 0, r, g, b] }

    init() {}
    init(mode: UInt8, brightness: UInt8 = 4, speed: UInt8 = 3, direction: UInt8 = 0,
         random: Bool, r: UInt8 = 255, g: UInt8 = 255, b: UInt8 = 255) {
        self.mode = mode; self.brightness = brightness; self.speed = speed; self.direction = direction
        self.random = random; self.r = r; self.g = g; self.b = b
    }
    init(bytes: [UInt8]) {
        mode = bytes[0]; brightness = min(bytes[1], 4); speed = min(bytes[2], 5); direction = bytes[3]
        random = bytes[4] != 0; r = bytes[5]; g = bytes[6]; b = bytes[7]
    }
}

enum GMMKError: LocalizedError {
    case notConnected, timeout(UInt8), writeFailed(IOReturn), deviceStatus(UInt8)
    var errorDescription: String? {
        switch self {
        case .notConnected: return "Keyboard not connected"
        case .timeout(let c): return String(format: "No reply to command 0x%02X", c)
        case .writeFailed(let r): return String(format: "USB write failed (0x%08X)", r)
        case .deviceStatus(let s): return "Keyboard rejected command (status \(s))"
        }
    }
}

/// Talks to the keyboard's vendor HID interface (usage page 0xFF1C) using the
/// EVision protocol documented by OpenRGB: 64-byte report 0x04, 16-bit checksum
/// over bytes 3..63, command at [3], size [4], offset [5..6], data from [8].
final class GMMKDevice {
    static let vendorID = 0x0C45, productID = 0x652F, usagePage = 0xFF1C

    enum Command: UInt8 { case begin = 0x01, end = 0x02, readConfig = 0x05, setParameter = 0x06 }

    /// Called on the main queue.
    var onConnectionChange: ((Bool) -> Void)?
    var onPermissionDenied: (() -> Void)?

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private let ioQueue = DispatchQueue(label: "gmmk.io")
    private let lock = NSLock()
    private var waitingCmd: UInt8?
    private var response: [UInt8]?
    private var responseSignal: DispatchSemaphore?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var pendingState: LightingState?
    private var applyScheduled = false

    var isConnected: Bool { lock.withLock { device != nil } }

    func start() {
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            self?.setUpManager()
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "GMMK HID"
        thread.start()
        ready.wait()
    }

    private func setUpManager() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey: Self.vendorID,
            kIOHIDProductIDKey: Self.productID,
            kIOHIDDeviceUsagePageKey: Self.usagePage,
        ]
        IOHIDManagerSetDeviceMatching(mgr, matching as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { ctx, _, _, dev in
            Unmanaged<GMMKDevice>.fromOpaque(ctx!).takeUnretainedValue().attached(dev)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { ctx, _, _, dev in
            Unmanaged<GMMKDevice>.fromOpaque(ctx!).takeUnretainedValue().removed(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) // non-exclusive
        if result == kIOReturnNotPermitted { DispatchQueue.main.async { self.onPermissionDenied?() } }
        manager = mgr
    }

    private func attached(_ dev: IOHIDDevice) {
        let open = IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        if open == kIOReturnNotPermitted {
            DispatchQueue.main.async { self.onPermissionDenied?() }
            return
        }
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, inputBuffer, 64, { ctx, _, _, _, _, report, length in
            Unmanaged<GMMKDevice>.fromOpaque(ctx!).takeUnretainedValue().received(report, length)
        }, ctx)
        lock.withLock { device = dev }
        DispatchQueue.main.async { self.onConnectionChange?(true) }
    }

    private func removed(_ dev: IOHIDDevice) {
        lock.withLock { if device == dev { device = nil } }
        DispatchQueue.main.async { self.onConnectionChange?(false) }
    }

    private func received(_ report: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
        var bytes = Array(UnsafeBufferPointer(start: report, count: length))
        if bytes.count == 63 { bytes.insert(0x04, at: 0) } // tolerate report ID being stripped
        guard bytes.count >= 8, bytes[0] == 0x04 else { return }
        lock.withLock {
            if let cmd = waitingCmd, bytes[3] == cmd {
                response = bytes
                waitingCmd = nil
                responseSignal?.signal()
            }
        }
    }

    /// Synchronous request/response. Must run on ioQueue (never on the HID run loop thread).
    private func transact(_ cmd: Command, offset: UInt16 = 0, data: [UInt8] = [], size: UInt8? = nil) throws -> [UInt8] {
        guard let dev = lock.withLock({ device }) else { throw GMMKError.notConnected }
        var buf = [UInt8](repeating: 0, count: 64)
        buf[0] = 0x04
        buf[3] = cmd.rawValue
        buf[4] = size ?? UInt8(data.count)
        buf[5] = UInt8(offset & 0xFF)
        buf[6] = UInt8(offset >> 8)
        buf.replaceSubrange(8..<(8 + data.count), with: data)
        let checksum = buf[3...].reduce(UInt16(0)) { $0 &+ UInt16($1) }
        buf[1] = UInt8(checksum & 0xFF)
        buf[2] = UInt8(checksum >> 8)

        let signal = DispatchSemaphore(value: 0)
        lock.withLock { waitingCmd = cmd.rawValue; response = nil; responseSignal = signal }
        let r = IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0x04, buf, buf.count)
        guard r == kIOReturnSuccess else {
            lock.withLock { waitingCmd = nil }
            throw GMMKError.writeFailed(r)
        }
        guard signal.wait(timeout: .now() + 1.0) == .success, let reply = lock.withLock({ response }) else {
            lock.withLock { waitingCmd = nil }
            throw GMMKError.timeout(cmd.rawValue)
        }
        if reply[7] != 0 { throw GMMKError.deviceStatus(reply[7]) }
        return reply
    }

    func readState(_ completion: @escaping (Result<LightingState, Error>) -> Void) {
        ioQueue.async {
            let result = Result { () throws -> LightingState in
                let reply = try self.transact(.readConfig, offset: 0, size: 8)
                return LightingState(bytes: Array(reply[8..<16]))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// Latest-wins: rapid slider changes collapse into one write.
    func apply(_ state: LightingState, completion: ((Error?) -> Void)? = nil) {
        lock.withLock { pendingState = state }
        let shouldSchedule = lock.withLock { () -> Bool in
            if applyScheduled { return false }
            applyScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        ioQueue.async {
            var lastError: Error?
            while let next = self.lock.withLock({ () -> LightingState? in
                let s = self.pendingState; self.pendingState = nil
                if s == nil { self.applyScheduled = false }
                return s
            }) {
                do {
                    _ = try self.transact(.begin)
                    _ = try self.transact(.setParameter, offset: 0, data: next.bytes)
                    _ = try self.transact(.end)
                    lastError = nil
                } catch {
                    lastError = error
                }
            }
            if let completion { DispatchQueue.main.async { completion(lastError) } }
        }
    }
}
