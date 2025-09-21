import Foundation

/// Representation of a 16-byte ring command packet.
struct RingCommand {
    let identifier: UInt8
    private let payload: [UInt8]

    init(identifier: UInt8, payload: [UInt8] = []) {
        precondition(payload.count <= 14, "Payload must be <= 14 bytes")
        self.identifier = identifier
        if payload.count < 14 {
            self.payload = payload + Array(repeating: 0x00, count: 14 - payload.count)
        } else {
            self.payload = payload
        }
    }

    /// Final packet to send to the ring, checksum included.
    var packet: Data {
        var bytes = [identifier]
        bytes.append(contentsOf: payload)
        let checksum = bytes.reduce(0) { (sum: Int, value: UInt8) in
            (sum + Int(value)) & 0xFF
        }
        bytes.append(UInt8(checksum))
        return Data(bytes)
    }

    /// Commands that do not expect a payload.
    static func simple(_ identifier: UInt8) -> RingCommand {
        RingCommand(identifier: identifier, payload: [])
    }

    /// Synchronises the ring RTC with the phone clock.
    static func syncTime(date: Date = Date()) -> RingCommand {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        let year = UInt16(components.year ?? 2024)
        let payload: [UInt8] = [
            UInt8(year & 0xFF),
            UInt8(year >> 8),
            UInt8(components.month ?? 1),
            UInt8(components.day ?? 1),
            UInt8(components.hour ?? 0),
            UInt8(components.minute ?? 0),
            UInt8(components.second ?? 0),
            UInt8((components.weekday ?? 1) - 1),
            0, 0, 0, 0, 0, 0
        ]
        return RingCommand(identifier: 0x01, payload: payload)
    }

    /// Requests the latest battery information.
    static func readBattery() -> RingCommand {
        RingCommand.simple(0x03)
    }

    /// Requests daily activity totals (steps, calories, distance).
    static func readActivity() -> RingCommand {
        RingCommand(identifier: 0x43, payload: [0x00, 0x00])
    }

    /// Requests the most recent heart rate measurement.
    static func readLatestHeartRate() -> RingCommand {
        RingCommand(identifier: 0x15, payload: [0x00, 0x00])
    }

    /// Requests the most recent SpO2 measurement.
    static func readLatestSpO2() -> RingCommand {
        RingCommand(identifier: 0x2C, payload: [0x02, 0x00])
    }

    /// Requests the most recent temperature measurement (supported on R06+).
    static func readTemperature() -> RingCommand {
        RingCommand(identifier: 0xBC, payload: [0x2A, 0x00])
    }

    /// Requests the latest stress/HRV analysis.
    static func readStress() -> RingCommand {
        RingCommand(identifier: 0x36, payload: [0x00, 0x00])
    }

    /// Requests aggregated sleep data for the last sleep session.
    static func readSleepSummary() -> RingCommand {
        RingCommand(identifier: 0xBC, payload: [0x27, 0x00])
    }

    /// Enables real-time heart rate streaming.
    static func startRealtime() -> RingCommand {
        RingCommand.simple(0x69)
    }

    /// Disables real-time heart rate streaming.
    static func stopRealtime() -> RingCommand {
        RingCommand.simple(0x6A)
    }

    /// Enables raise/wave gesture detection (for models that support it).
    static func enableGestureDetection() -> RingCommand {
        RingCommand(identifier: 0x02, payload: [0x04, 0x01])
    }

    /// Disables gesture detection.
    static func disableGestureDetection() -> RingCommand {
        RingCommand(identifier: 0x02, payload: [0x04, 0x00])
    }
}
