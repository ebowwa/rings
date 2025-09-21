import Foundation

/// Utility for decoding raw 16-byte packets emitted by the ring into
/// high level updates the UI can consume.
struct RingResponseParser {
    func parse(_ data: Data) -> [RingMetricsUpdate] {
        guard data.count == 16 else {
            return [.log("Unexpected packet length: \(data.count) bytes")] 
        }

        let bytes = [UInt8](data)
        let checksum = bytes.dropLast().reduce(0) { (sum: Int, value: UInt8) in
            (sum + Int(value)) & 0xFF
        }
        guard checksum == Int(bytes.last ?? 0) else {
            return [.log("Checksum mismatch for command 0x\(String(bytes[0], radix: 16))")]
        }

        let rawCommand = bytes[0]
        let command = rawCommand & 0x7F
        let isError = (rawCommand & 0x80) != 0
        if isError {
            return [.log("Ring responded with error for command 0x\(String(command, radix: 16))")] 
        }

        switch command {
        case 0x01:
            return parseSupportFlags(bytes)
        case 0x03:
            return parseBattery(bytes)
        case 0x15:
            return parseHeartRate(bytes)
        case 0x2C:
            return parseSpO2(bytes)
        case 0x36:
            return parseStress(bytes)
        case 0x43:
            return parseActivity(bytes)
        case 0x69:
            return parseRealtime(bytes)
        case 0xBC:
            return parseExtended(bytes)
        default:
            return [.log("Unhandled command response 0x\(String(command, radix: 16))")] 
        }
    }

    private func parseSupportFlags(_ bytes: [UInt8]) -> [RingMetricsUpdate] {
        guard bytes.count >= 10 else { return [.log("Support flag payload too short")] }
        let flags1 = bytes[8]
        _ = bytes[9]

        var support: RingFeatureSupport = []
        if (flags1 & 0x01) != 0 { support.insert(.heartRate) }
        if (flags1 & 0x02) != 0 { support.insert(.spo2) }
        if (flags1 & 0x04) != 0 { support.insert(.temperature) }
        if (flags1 & 0x08) != 0 { support.insert(.gesture) }
        if (flags1 & 0x10) != 0 { support.insert(.rawSensors) }
        if (flags1 & 0x20) != 0 { support.insert(.stress) }
        if (flags1 & 0x40) != 0 { support.insert(.sleep) }

        // Some firmwares expose extended flags in flags2, keep log for now.
        return [.supportFlags(support), .handshakeComplete]
    }

    private func parseBattery(_ bytes: [UInt8]) -> [RingMetricsUpdate] {
        guard bytes.count >= 3 else { return [.log("Battery payload too short")] }
        let level = Int(bytes[1])
        let charging = bytes[2] != 0
        return [.battery(level: level, charging: charging)]
    }

    private func parseHeartRate(_ bytes: [UInt8]) -> [RingMetricsUpdate] {
        guard bytes.count >= 3 else { return [.log("Heart rate payload too short")] }
        let bpm = Int(bytes[1])
        return [.heartRate(current: bpm)]
    }

    private func parseSpO2(_ bytes: [UInt8]) -> [RingMetricsUpdate] {
        guard bytes.count >= 3 else { return [.log("SpO2 payload too short")] }
        let spo2 = Int(bytes[1])
        return [.spo2(value: spo2)]
    }

    private func parseStress(_ bytes: [UInt8]) -> [RingMetricsUpdate] {
        guard bytes.count >= 4 else { return [.log("Stress payload too short")] }
        let stressLevel = Int(bytes[1])
        let hrv = bytes[2] == 0xFF ? nil : Int(bytes[2])
        return [.stress(level: stressLevel, hrv: hrv)]
    }

    private func parseActivity(_ bytes: [UInt8]) -> [RingMetricsUpdate] {
        guard bytes.count >= 13 else { return [.log("Activity payload too short")] }
        let steps = decode24Bit(bytes[1], bytes[2], bytes[3])
        let calories = decode24Bit(bytes[4], bytes[5], bytes[6])
        let distance = decode24Bit(bytes[7], bytes[8], bytes[9])
        return [.activity(steps: steps, calories: calories, distance: distance)]
    }

    private func parseRealtime(_ bytes: [UInt8]) -> [RingMetricsUpdate] {
        guard bytes.count >= 4 else { return [.log("Realtime payload too short")] }
        // Byte1: data type (0x01 = heart rate, 0x02 = SpO2, 0x03 = temperature stream)
        let dataType = bytes[1]
        let value = bytes[2]
        switch dataType {
        case 0x01:
            return [.heartRate(current: Int(value))]
        case 0x02:
            return [.spo2(value: Int(value))]
        case 0x03:
            let tempC = Double(Int16(bitPattern: UInt16(value) | (UInt16(bytes[3]) << 8))) / 100.0
            return [.temperature(celsius: tempC)]
        default:
            return [.log("Unhandled realtime data type 0x\(String(dataType, radix: 16))")] 
        }
    }

    private func parseExtended(_ bytes: [UInt8]) -> [RingMetricsUpdate] {
        guard bytes.count >= 3 else { return [.log("Extended payload too short")] }
        let subCommand = bytes[1]
        switch subCommand {
        case 0x27:
            return parseSleep(bytes)
        case 0x2A:
            return parseTemperature(bytes)
        default:
            return [.log("Unhandled extended sub-command 0x\(String(subCommand, radix: 16))")] 
        }
    }

    private func parseTemperature(_ bytes: [UInt8]) -> [RingMetricsUpdate] {
        guard bytes.count >= 6 else { return [.log("Temperature payload too short")] }
        let raw = UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
        let temperature = Double(Int16(bitPattern: raw)) / 100.0
        return [.temperature(celsius: temperature)]
    }

    private func parseSleep(_ bytes: [UInt8]) -> [RingMetricsUpdate] {
        guard bytes.count >= 10 else { return [.log("Sleep payload too short")] }
        let total = decode16Bit(bytes[2], bytes[3])
        let deep = decode16Bit(bytes[4], bytes[5])
        let light = decode16Bit(bytes[6], bytes[7])
        let rem = decode16Bit(bytes[8], bytes[9])
        let awake = max(0, total - deep - light - rem)
        let summary = RingSleepSummary(totalMinutes: total, lightMinutes: light, deepMinutes: deep, remMinutes: rem, awakeMinutes: awake)
        return [.sleep(summary: summary)]
    }

    private func decode24Bit(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8) -> Int {
        Int(UInt32(b0) | (UInt32(b1) << 8) | (UInt32(b2) << 16))
    }

    private func decode16Bit(_ b0: UInt8, _ b1: UInt8) -> Int {
        Int(UInt16(b0) | (UInt16(b1) << 8))
    }
}
