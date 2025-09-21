import SwiftUI

struct ContentView: View {
    @StateObject private var manager = RingBLEManager()

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                metricsSection
                healthSection
                sleepSection
                stressSection
                logsSection
            }
            .navigationTitle("Ring Dashboard")
            .toolbar { refreshButton }
            .task { manager.startScanning() }
            .alert(item: $manager.error) { error in
                Alert(title: Text("Error"), message: Text(error.localizedDescription), dismissButton: .default(Text("OK")))
            }
        }
    }

    private var connectionSection: some View {
        Section("Connection") {
            LabeledContent("State", value: connectionDescription)
                .foregroundStyle(.secondary)

            if case .scanning = manager.connectionState {
                ProgressView()
            }

            if manager.discoveredDevices.isEmpty {
                Button("Scan for Rings") { manager.startScanning() }
            } else {
                ForEach(manager.discoveredDevices) { device in
                    Button {
                        manager.connect(to: device.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(device.name)
                            Text("RSSI: \(device.rssi) dBm")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if isConnected {
                Button("Disconnect", role: .destructive) { manager.disconnect() }
            }

            if !supportDescriptions.isEmpty {
                Text("Supported: \(supportDescriptions.joined(separator: ", "))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var metricsSection: some View {
        Section("At a Glance") {
            MetricRow(icon: "battery.100", title: "Battery", value: formattedBattery)
            MetricRow(icon: "clock", title: "Last Sync", value: formattedLastSync)
            MetricRow(icon: "figure.walk", title: "Steps", value: formattedSteps)
            MetricRow(icon: "flame", title: "Calories", value: formattedCalories)
            MetricRow(icon: "map", title: "Distance", value: formattedDistance)
        }
    }

    private var healthSection: some View {
        Section("Vitals") {
            MetricRow(icon: "heart.fill", title: "Heart Rate", value: formattedHeartRate)
            MetricRow(icon: "lungs.fill", title: "SpO₂", value: formattedSpO2)
            MetricRow(icon: "thermometer", title: "Temperature", value: formattedTemperature)
        }
    }

    private var sleepSection: some View {
        Section("Sleep") {
            MetricRow(icon: "bed.double.fill", title: "Total", value: minutesString(manager.metrics.sleepSummary.totalMinutes))
            MetricRow(icon: "moon.zzz.fill", title: "Deep", value: minutesString(manager.metrics.sleepSummary.deepMinutes))
            MetricRow(icon: "sparkles", title: "REM", value: minutesString(manager.metrics.sleepSummary.remMinutes))
            MetricRow(icon: "cloud.fill", title: "Light", value: minutesString(manager.metrics.sleepSummary.lightMinutes))
            MetricRow(icon: "sunrise.fill", title: "Awake", value: minutesString(manager.metrics.sleepSummary.awakeMinutes))
        }
    }

    private var stressSection: some View {
        Section("Stress & HRV") {
            MetricRow(icon: "waveform.path.ecg", title: "Stress", value: formattedStress)
            MetricRow(icon: "bolt.heart", title: "HRV", value: formattedHRV)
        }
    }

    private var logsSection: some View {
        Section("Logs") {
            ForEach(Array(manager.logs.suffix(8))) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.message)
                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var refreshButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                manager.refreshMetrics()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(!isConnected)
        }
    }

    private var isConnected: Bool {
        switch manager.connectionState {
        case .ready, .connected:
            return true
        default:
            return false
        }
    }

    private var connectionDescription: String {
        switch manager.connectionState {
        case .idle: return "Idle"
        case .scanning: return "Scanning"
        case .connecting(let name): return "Connecting to \(name)"
        case .connected(let name): return "Connected to \(name)"
        case .ready(let name): return "Ready (\(name))"
        case .error(let message): return "Error: \(message)"
        }
    }

    private var formattedBattery: String {
        guard let level = manager.metrics.batteryPercentage else { return "–" }
        return "\(level)%" + (manager.metrics.isCharging ? " ⚡️" : "")
    }

    private var formattedLastSync: String {
        guard let lastSync = manager.metrics.lastSynced else { return "–" }
        return lastSync.formatted(date: .omitted, time: .shortened)
    }

    private var formattedSteps: String {
        guard let steps = manager.metrics.steps else { return "–" }
        return NumberFormatter.steps.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }

    private var formattedCalories: String {
        guard let calories = manager.metrics.calories else { return "–" }
        return "\(calories) kcal"
    }

    private var formattedDistance: String {
        guard let distance = manager.metrics.distanceMeters else { return "–" }
        let kilometers = Double(distance) / 1000.0
        return String(format: "%.2f km", kilometers)
    }

    private var formattedHeartRate: String {
        guard let bpm = manager.metrics.heartRate else { return "–" }
        return "\(bpm) bpm"
    }

    private var formattedSpO2: String {
        guard let spo2 = manager.metrics.spo2 else { return "–" }
        return "\(spo2)%"
    }

    private var formattedTemperature: String {
        guard let temp = manager.metrics.bodyTemperatureCelsius else { return "–" }
        return String(format: "%.2f ℃", temp)
    }

    private var formattedStress: String {
        guard let stress = manager.metrics.stressLevel else { return "–" }
        return "\(stress)"
    }

    private var formattedHRV: String {
        guard let hrv = manager.metrics.hrv else { return "–" }
        return "\(hrv) ms"
    }

    private var supportDescriptions: [String] {
        var items: [String] = []
        if manager.supportFlags.contains(.heartRate) { items.append("Heart rate") }
        if manager.supportFlags.contains(.spo2) { items.append("SpO₂") }
        if manager.supportFlags.contains(.temperature) { items.append("Temperature") }
        if manager.supportFlags.contains(.gesture) { items.append("Gestures") }
        if manager.supportFlags.contains(.rawSensors) { items.append("Raw sensors") }
        if manager.supportFlags.contains(.stress) { items.append("Stress") }
        if manager.supportFlags.contains(.sleep) { items.append("Sleep") }
        return items
    }

    private func minutesString(_ minutes: Int) -> String {
        guard minutes > 0 else { return "–" }
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainder)m"
        }
        return "\(minutes)m"
    }
}

private struct MetricRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading) {
                Text(title)
                Text(value)
                    .font(.headline)
            }
        }
    }
}

private extension NumberFormatter {
    static let steps: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}
