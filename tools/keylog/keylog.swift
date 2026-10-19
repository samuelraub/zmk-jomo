// Logs suspicious key timings from the Jomo, as seen by the host (see #6).
// Only anomalies are written, never the typed text.
//
//   swiftc -O tools/keylog/keylog.swift -o tools/keylog/keylog
//   tools/keylog/keylog [logfile]   (default ~/Library/Logs/jomo-keylog.log)

import Foundation
import IOKit.hid

let vendorID = 0x1D50
let productID = 0x615E

// A second press this soon after a release can't come from a finger.
let chatterMs = 40.0
// Holds this long are logged even below the repeat threshold, to show the spread.
let longHoldMs = 180.0
// Holds past this are deliberate (e.g. holding Bspc) and not logged.
let deliberateMs = 1000.0

let logPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : NSString(string: "~/Library/Logs/jomo-keylog.log").expandingTildeInPath

// .standard falls back to the global domain, where these live.
let defaults = UserDefaults.standard
let initialRepeatMs = Double(defaults.object(forKey: "InitialKeyRepeat") as? Int ?? 25) * 15
let repeatMs = Double(defaults.object(forKey: "KeyRepeat") as? Int ?? 6) * 15

var timebase = mach_timebase_info_data_t()
mach_timebase_info(&timebase)
func ms(_ t: UInt64) -> Double {
    Double(t) * Double(timebase.numer) / Double(timebase.denom) / 1e6
}

let stamp = DateFormatter()
stamp.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

if !FileManager.default.fileExists(atPath: logPath) {
    FileManager.default.createFile(atPath: logPath, contents: nil)
}
let log = FileHandle(forWritingAtPath: logPath)!
log.seekToEndOfFile()
func write(_ line: String) {
    let out = "\(stamp.string(from: Date()))  \(line)\n"
    log.write(out.data(using: .utf8)!)
    FileHandle.standardOutput.write(out.data(using: .utf8)!)
}

func keyName(_ usage: Int) -> String {
    switch usage {
    case 0x04...0x1D: return String(UnicodeScalar(UInt8(0x41 + usage - 0x04)))
    case 0x1E...0x26: return String(usage - 0x1D)
    case 0x27: return "0"
    case 0x28: return "Return"
    case 0x29: return "Esc"
    case 0x2A: return "Bspc"
    case 0x2B: return "Tab"
    case 0x2C: return "Space"
    case 0x4C: return "Del"
    case 0x4F: return "Right"
    case 0x50: return "Left"
    case 0x51: return "Down"
    case 0x52: return "Up"
    default: return String(format: "0x%02X", usage)
    }
}

func repeats(_ holdMs: Double) -> Int {
    holdMs < initialRepeatMs ? 0 : 1 + Int((holdMs - initialRepeatMs) / repeatMs)
}

var pressedAt: [Int: UInt64] = [:]
var releasedAt: [Int: UInt64] = [:]
var modEdgeAt: UInt64 = 0
var presses = 0
var flagged = 0

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDVendorIDKey: vendorID,
    kIOHIDProductIDKey: productID,
    kIOHIDPrimaryUsagePageKey: kHIDPage_GenericDesktop,
    kIOHIDPrimaryUsageKey: kHIDUsage_GD_Keyboard,
] as CFDictionary)

IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
    let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "?"
    write("connected via \(transport)")
}, nil)
IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, device in
    let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "?"
    write("disconnected (\(transport))")
}, nil)

IOHIDManagerRegisterInputValueCallback(manager, { _, _, _, value in
    let element = IOHIDValueGetElement(value)
    let usage = Int(IOHIDElementGetUsage(element))
    guard IOHIDElementGetUsagePage(element) == kHIDPage_KeyboardOrKeypad else { return }
    let t = IOHIDValueGetTimeStamp(value)
    // Modifiers never autorepeat; they're only tracked to spot keys like LC(A),
    // whose modifier arrives in the same report.
    if (0xE0...0xE7).contains(usage) {
        modEdgeAt = t
        return
    }
    // Letters through keypad.
    guard (0x04...0xA4).contains(usage) else { return }
    let link = IOHIDDeviceGetProperty(IOHIDElementGetDevice(element), kIOHIDTransportKey as CFString) as? String == "USB" ? "USB" : "BLE"
    let name = "\(link)  \(keyName(usage))"

    if IOHIDValueGetIntegerValue(value) != 0 {
        presses += 1
        // A macro tapping LC(A) twice re-presses A within ms; a switch can't add Ctrl.
        if let up = releasedAt[usage], ms(t - up) < chatterMs {
            // The report's modifiers are delivered after its keys, so decide once it's all in.
            DispatchQueue.main.async {
                guard modEdgeAt != t else { return }
                flagged += 1
                write("CHATTER  \(name)  pressed again \(String(format: "%.1f", ms(t - up))) ms after release")
            }
        }
        pressedAt[usage] = t
    } else if let down = pressedAt.removeValue(forKey: usage) {
        releasedAt[usage] = t
        let hold = ms(t - down)
        let n = repeats(hold)
        if hold >= longHoldMs && hold < deliberateMs {
            if n > 0 { flagged += 1 }
            let tag = n > 0 ? "REPEAT  " : "LONG    "
            write("\(tag) \(name)  held \(Int(hold)) ms -> \(n) autorepeat")
        }
    }
}, nil)

IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard result == kIOReturnSuccess else {
    print("Can't open HID devices (\(String(format: "0x%08X", result))).")
    print("Grant Input Monitoring to your terminal: System Settings > Privacy & Security > Input Monitoring.")
    IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    exit(1)
}

write("started; autorepeat after \(Int(initialRepeatMs)) ms, then every \(Int(repeatMs)) ms")

Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
    write("hourly: \(presses) presses, \(flagged) flagged")
}

signal(SIGINT) { _ in
    write("stopped: \(presses) presses, \(flagged) flagged")
    exit(0)
}

CFRunLoopRun()
