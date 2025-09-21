import Foundation
import CoreBluetooth
import Combine

/// Centralised BLE manager responsible for scanning, connecting and exchanging
/// command packets with the COLMI ring.
final class RingBLEManager: NSObject, ObservableObject {
    @Published private(set) var connectionState: RingConnectionState = .idle
    @Published private(set) var discoveredDevices: [RingDeviceSummary] = []
    @Published private(set) var metrics: RingMetrics = .empty
    @Published private(set) var supportFlags: RingFeatureSupport = .none
    @Published private(set) var logs: [RingLogEntry] = []
    @Published var error: RingError?

    private let configuration: RingConfiguration
    private let parser = RingResponseParser()
    private lazy var centralManager: CBCentralManager = CBCentralManager(delegate: self, queue: nil)

    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connectedPeripheral: CBPeripheral?

    private var commandCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var commandQueue: [RingCommand] = []
    private var isWritingCommand = false
    private var shouldResumeScan = false

    private let commandService = CBUUID(string: "6E40FFF0-B5A3-F393-E0A9-E50E24DCCA9E")
    private let commandWriteCharacteristic = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let commandNotifyCharacteristic = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    private let bigDataService = CBUUID(string: "DE5BF728-D711-4E47-AF26-65E3012A5DC7")
    private let bigDataWriteCharacteristic = CBUUID(string: "DE5BF72A-D711-4E47-AF26-65E3012A5DC7")
    private let bigDataNotifyCharacteristic = CBUUID(string: "DE5BF729-D711-4E47-AF26-65E3012A5DC7")

    private var reconnectCancellable: AnyCancellable?

    init(configuration: RingConfiguration = RingConfiguration()) {
        self.configuration = configuration
        super.init()
    }

    func startScanning() {
        switch centralManager.state {
        case .poweredOn:
            shouldResumeScan = false
        case .poweredOff:
            error = .bluetoothUnavailable
            appendLog("Cannot scan: Bluetooth powered off")
            connectionState = .idle
            return
        default:
            appendLog("Bluetooth not ready, will start scan once powered on")
            shouldResumeScan = true
            return
        }
        appendLog("Starting scan")
        connectionState = .scanning
        discoveredDevices.removeAll()
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScanning() {
        centralManager.stopScan()
        if case .scanning = connectionState {
            connectionState = .idle
        }
    }

    func connect(to deviceID: UUID) {
        guard let peripheral = peripherals[deviceID] else { return }
        appendLog("Connecting to \(peripheral.displayName)")
        stopScanning()
        connectionState = .connecting(peripheral.displayName)
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        appendLog("Disconnecting from \(peripheral.displayName)")
        if commandCharacteristic != nil {
            enqueue(.stopRealtime())
        }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func refreshMetrics() {
        enqueue(.readBattery())
        enqueue(.readActivity())
        enqueue(.readLatestHeartRate())
        if supportFlags.contains(.spo2) {
            enqueue(.readLatestSpO2())
        }
        if supportFlags.contains(.temperature) {
            enqueue(.readTemperature())
        }
        if supportFlags.contains(.stress) {
            enqueue(.readStress())
        }
        if supportFlags.contains(.sleep) {
            enqueue(.readSleepSummary())
        }
    }

    private func handshakeSequence() {
        enqueue(.syncTime())
        enqueue(.readBattery())
        enqueue(.readActivity())
        enqueue(.readLatestHeartRate())
    }

    private func enqueue(_ command: RingCommand) {
        commandQueue.append(command)
        flushCommandQueue()
    }

    private func flushCommandQueue() {
        guard !isWritingCommand,
              !commandQueue.isEmpty,
              let peripheral = connectedPeripheral,
              let characteristic = commandCharacteristic else { return }

        isWritingCommand = true
        let command = commandQueue.removeFirst()
        appendLog("-> 0x\(String(format: "%02X", command.identifier))")
        peripheral.writeValue(command.packet, for: characteristic, type: .withResponse)
    }

    private func appendLog(_ message: String) {
        logs.append(RingLogEntry(message: message))
        if logs.count > 200 {
            logs.removeFirst(logs.count - 200)
        }
    }

    private func handleUpdates(from data: Data) {
        for update in parser.parse(data) {
            switch update {
            case .supportFlags(let flags):
                supportFlags = flags
                appendLog("Support flags: \(flags)")
                refreshMetrics()
                if flags.contains(.heartRate) && configuration.enableRealtimeHeartRate {
                    enqueue(.startRealtime())
                }
                if flags.contains(.gesture) {
                    enqueue(.enableGestureDetection())
                }
                if flags.contains(.spo2) && configuration.enableRealtimeSpO2 {
                    enqueue(.startRealtime())
                }
            case .handshakeComplete:
                connectionState = .ready(connectedPeripheral?.displayName ?? "Ring")
            case .log(let message):
                appendLog(message)
            default:
                metrics.apply(update)
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension RingBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            appendLog("Bluetooth powered on")
            if shouldResumeScan {
                startScanning()
            }
        case .poweredOff:
            error = .bluetoothUnavailable
            connectionState = .idle
        case .unauthorized:
            error = .permissionsDenied
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.displayName
        guard name.uppercased().hasPrefix("R0") else { return }
        peripherals[peripheral.identifier] = peripheral
        peripheral.delegate = self
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let summary = RingDeviceSummary(
            id: peripheral.identifier,
            name: name,
            rssi: RSSI.intValue,
            advertisementData: advertisementData,
            supportsBigDataService: advertisedServices.contains(bigDataService)
        )
        if let index = discoveredDevices.firstIndex(where: { $0.id == summary.id }) {
            discoveredDevices[index] = summary
        } else {
            discoveredDevices.append(summary)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        appendLog("Connected to \(peripheral.displayName)")
        connectedPeripheral = peripheral
        commandCharacteristic = nil
        notifyCharacteristic = nil
        commandQueue.removeAll()
        metrics = .empty
        supportFlags = .none
        connectionState = .connected(peripheral.displayName)
        peripheral.discoverServices([commandService, bigDataService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        appendLog("Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        commandQueue.removeAll()
        connectionState = .idle
        self.error = .connectionFailed(error?.localizedDescription ?? "Unknown error")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        appendLog("Disconnected from \(peripheral.displayName)")
        commandQueue.removeAll()
        commandCharacteristic = nil
        notifyCharacteristic = nil
        connectedPeripheral = nil
        connectionState = .idle

        if configuration.autoReconnect, error == nil {
            reconnectCancellable = Just(peripheral)
                .delay(for: .seconds(2), scheduler: RunLoop.main)
                .sink { [weak self] peripheral in
                    guard let self else { return }
                    self.appendLog("Attempting auto reconnect")
                    self.centralManager.connect(peripheral, options: nil)
                }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension RingBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            appendLog("Service discovery error: \(error.localizedDescription)")
            self.error = .connectionFailed(error.localizedDescription)
            return
        }
        guard let services = peripheral.services else { return }
        for service in services {
            switch service.uuid {
            case commandService:
                peripheral.discoverCharacteristics([commandWriteCharacteristic, commandNotifyCharacteristic], for: service)
            case bigDataService:
                peripheral.discoverCharacteristics([bigDataWriteCharacteristic, bigDataNotifyCharacteristic], for: service)
            default:
                break
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            appendLog("Characteristic discovery error: \(error.localizedDescription)")
            self.error = .connectionFailed(error.localizedDescription)
            return
        }

        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            switch characteristic.uuid {
            case commandWriteCharacteristic:
                commandCharacteristic = characteristic
            case commandNotifyCharacteristic:
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            case bigDataNotifyCharacteristic:
                peripheral.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }

        if commandCharacteristic != nil && notifyCharacteristic != nil {
            appendLog("Command channel ready")
            handshakeSequence()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("Notify state error: \(error.localizedDescription)")
        } else {
            appendLog("Notifications enabled for \(characteristic.uuid.uuidString)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("Read error: \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        appendLog("<- \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")
        handleUpdates(from: data)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        isWritingCommand = false
        if let error {
            appendLog("Write error: \(error.localizedDescription)")
        }
        flushCommandQueue()
    }
}

private extension CBPeripheral {
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return identifier.uuidString
    }
}
