import Testing
@testable import ring

struct RingCommandTests {
    @Test("Ring command checksum and padding")
    func commandPacket() throws {
        let command = RingCommand(identifier: 0x03, payload: [0x01, 0x02])
        let packet = [UInt8](command.packet)
        #expect(packet.count == 16)
        #expect(packet[0] == 0x03)
        // payload padded with zeros up to 14 bytes
        #expect(packet[1] == 0x01)
        #expect(packet[2] == 0x02)
        #expect(packet[3] == 0x00)
        // checksum is sum modulo 0xFF
        let checksum = packet.dropLast().reduce(0) { ($0 + Int($1)) & 0xFF }
        #expect(packet.last == UInt8(checksum))
    }
}

struct RingResponseParserTests {
    private let parser = RingResponseParser()

    @Test("Parses battery payload")
    func batteryParsing() {
        var bytes: [UInt8] = [0x03, 85, 1]
        bytes.append(contentsOf: Array(repeating: 0x00, count: 12))
        let checksum = bytes.reduce(0) { ($0 + Int($1)) & 0xFF }
        bytes.append(UInt8(checksum))
        let updates = parser.parse(Data(bytes))
        #expect(updates.contains { if case .battery(level: 85, charging: true) = $0 { return true } else { return false } })
    }

    @Test("Parses activity payload")
    func activityParsing() {
        var bytes: [UInt8] = [0x43, 0x10, 0x27, 0x00, 0x20, 0x4E, 0x00, 0x30, 0x75, 0x00]
        bytes.append(contentsOf: Array(repeating: 0x00, count: 5))
        let checksum = bytes.reduce(0) { ($0 + Int($1)) & 0xFF }
        bytes.append(UInt8(checksum))
        let updates = parser.parse(Data(bytes))
        let foundActivity = updates.contains { update in
            if case .activity(let steps, let calories, let distance) = update {
                return steps == 0x002710 && calories == 0x004E20 && distance == 0x007530
            }
            return false
        }
        #expect(foundActivity)
    }
}
