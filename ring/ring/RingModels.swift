import Foundation
import CoreBluetooth

/// Represents a COLMI ring that has been discovered during scanning.
struct RingDeviceSummary: Identifiable {
    let id: UUID
    let name: String
    let rssi: Int
    let advertisementData: [String: Any]
    let supportsBigDataService: Bool
}

/// Connection lifecycle states for the ring peripheral.
enum RingConnectionState: Equatable {
    case idle
    case scanning
    case connecting(String)
    case connected(String)
    case ready(String)
    case error(String)
}

/// Flags describing which features are actually available on the ring hardware.
struct RingFeatureSupport: OptionSet {
    let rawValue: Int

    static let heartRate      = RingFeatureSupport(rawValue: 1 << 0)
    static let spo2           = RingFeatureSupport(rawValue: 1 << 1)
    static let temperature    = RingFeatureSupport(rawValue: 1 << 2)
    static let gesture        = RingFeatureSupport(rawValue: 1 << 3)
    static let rawSensors     = RingFeatureSupport(rawValue: 1 << 4)
    static let stress         = RingFeatureSupport(rawValue: 1 << 5)
    static let sleep          = RingFeatureSupport(rawValue: 1 << 6)

    static let none: RingFeatureSupport = []
}

/// Aggregated metrics that the MVP surfaces in the UI.
struct RingMetrics {
    var lastSynced: Date?
    var batteryPercentage: Int?
    var isCharging: Bool = false

    var heartRate: Int?
    var spo2: Int?
    var bodyTemperatureCelsius: Double?

    var steps: Int?
    var calories: Int?
    var distanceMeters: Int?

    var stressLevel: Int?
    var hrv: Int?

    var sleepSummary: RingSleepSummary = .empty

    static let empty = RingMetrics()
}

/// High-level sleep statistics summarised per synchronization.
struct RingSleepSummary {
    var totalMinutes: Int
    var lightMinutes: Int
    var deepMinutes: Int
    var remMinutes: Int
    var awakeMinutes: Int

    static let empty = RingSleepSummary(totalMinutes: 0, lightMinutes: 0, deepMinutes: 0, remMinutes: 0, awakeMinutes: 0)
}

/// Updates emitted by the BLE layer when new data is parsed from the ring.
enum RingMetricsUpdate {
    case battery(level: Int, charging: Bool)
    case heartRate(current: Int)
    case spo2(value: Int)
    case temperature(celsius: Double)
    case activity(steps: Int, calories: Int, distance: Int)
    case stress(level: Int, hrv: Int?)
    case sleep(summary: RingSleepSummary)
    case supportFlags(RingFeatureSupport)
    case handshakeComplete
    case log(String)
}

/// MVP specific configuration to control automatic behaviours.
struct RingConfiguration {
    var autoReconnect: Bool = true
    var enableRealtimeHeartRate: Bool = true
    var enableRealtimeSpO2: Bool = false
}

extension RingFeatureSupport: CustomStringConvertible {
    var description: String {
        var features: [String] = []
        if contains(.heartRate) { features.append("heartRate") }
        if contains(.spo2) { features.append("spo2") }
        if contains(.temperature) { features.append("temperature") }
        if contains(.gesture) { features.append("gesture") }
        if contains(.rawSensors) { features.append("rawSensors") }
        if contains(.stress) { features.append("stress") }
        if contains(.sleep) { features.append("sleep") }
        return features.isEmpty ? "none" : features.joined(separator: ", ")
    }
}

extension RingMetrics {
    mutating func apply(_ update: RingMetricsUpdate) {
        switch update {
        case let .battery(level, charging):
            batteryPercentage = level
            isCharging = charging
            lastSynced = Date()
        case let .heartRate(current):
            heartRate = current
            lastSynced = Date()
        case let .spo2(value):
            spo2 = value
            lastSynced = Date()
        case let .temperature(celsius):
            bodyTemperatureCelsius = celsius
            lastSynced = Date()
        case let .activity(stepCount, caloriesValue, distance):
            steps = stepCount
            calories = caloriesValue
            distanceMeters = distance
            lastSynced = Date()
        case let .stress(level, hrvValue):
            stressLevel = level
            hrv = hrvValue
            lastSynced = Date()
        case let .sleep(summary):
            sleepSummary = summary
            lastSynced = Date()
        case .supportFlags, .handshakeComplete, .log:
            break
        }
    }
}

/// Lightweight log entry used to bubble BLE events up to the UI.
struct RingLogEntry: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
}

/// Errors surfaced by the MVP. Many BLE errors are transient, so this keeps them user friendly.
enum RingError: Error, Identifiable {
    case bluetoothUnavailable
    case permissionsDenied
    case connectionFailed(String)
    case characteristicMissing
    case unsupportedFeature(String)

    var id: String { localizedDescription }

    var localizedDescription: String {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is unavailable. Enable Bluetooth to connect to the ring."
        case .permissionsDenied:
            return "Bluetooth permissions are required to talk to the ring."
        case let .connectionFailed(reason):
            return "Connection failed: \(reason)"
        case .characteristicMissing:
            return "Required Bluetooth characteristics were not found on the ring."
        case let .unsupportedFeature(name):
            return "The ring does not support \(name)."
        }
    }
}
