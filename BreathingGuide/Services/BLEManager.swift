//
//  BLEManager.swift
//  BreathingGuide
//
//  Created by Steven Bailey on 11/4/25.
//  Updated to use a dedicated BLE queue (QoS: .userInitiated) to avoid priority inversions,
//  and to publish state changes on the main thread.

//  Defers BLE scanning until after the app becomes active (post-first-frame)
//  to avoid launch-time QoS priority inversions flagged at App init.
//

import Foundation
import CoreBluetooth
import UIKit

final class BLEManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    // Published vitals / device
    @Published var connectedBPDevice: CBPeripheral?
    @Published var systolic: Double?
    @Published var diastolic: Double?
    @Published var heartRate: Double?

    // CoreBluetooth
    private var centralManager: CBCentralManager!
    private var bpPeripheral: CBPeripheral?

    // Use a dedicated high-QoS queue for CoreBluetooth work
    private let centralQueue = DispatchQueue(label: "com.breathingguide.ble.central",
                                             qos: .userInitiated)

    // Services/Characteristics
    private let bpServiceUUID = CBUUID(string: "1810")   // Blood Pressure Service
    private let bpMeasurementUUID = CBUUID(string: "2A35")
    private let heartRateServiceUUID = CBUUID(string: "180D")
    private let heartRateMeasurementUUID = CBUUID(string: "2A37")

    // Scanning control
    private var hasRequestedScan = false
    private var appActiveObserver: NSObjectProtocol?

    override init() {
        super.init()

        // Initialize CBCentralManager on our high-QoS queue (not main)
        centralManager = CBCentralManager(delegate: self, queue: centralQueue, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])

        // Defer scanning until the app has become active (post-first-frame).
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.requestScanAfterAppActive()
        }
    }

    deinit {
        if let obs = appActiveObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    // MARK: - Scan control

    private func requestScanAfterAppActive() {
        hasRequestedScan = true
        centralQueue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.startScanIfPossible()
        }
    }

    private func startScanIfPossible() {
        guard centralManager.state == .poweredOn else { return }
        guard hasRequestedScan else { return }

        centralManager.scanForPeripherals(
            withServices: [bpServiceUUID, heartRateServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func stopScan() {
        centralManager.stopScan()
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            centralQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.startScanIfPossible()
            }
        default:
            stopScan()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {

        bpPeripheral = peripheral
        stopScan()
        centralManager.connect(peripheral, options: nil)

        DispatchQueue.main.async {
            self.connectedBPDevice = peripheral
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([bpServiceUUID, heartRateServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            if self.connectedBPDevice == peripheral { self.connectedBPDevice = nil }
        }
        centralQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startScanIfPossible()
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        DispatchQueue.main.async {
            if self.connectedBPDevice == peripheral { self.connectedBPDevice = nil }
        }
        centralQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.startScanIfPossible()
        }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([bpMeasurementUUID, heartRateMeasurementUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil, let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard error == nil, let data = characteristic.value else { return }

        if characteristic.uuid == bpMeasurementUUID {
            parseBPData(data)
        } else if characteristic.uuid == heartRateMeasurementUUID {
            parseHRData(data)
        }
    }

    // MARK: - Parsing (simplified)
    private func parseBPData(_ data: Data) {
        guard data.count >= 4 else { return }
        let systolicRaw = UInt16(data[1]) << 8 | UInt16(data[0])
        let diastolicRaw = UInt16(data[3]) << 8 | UInt16(data[2])

        DispatchQueue.main.async {
            self.systolic = Double(systolicRaw)
            self.diastolic = Double(diastolicRaw)
        }
    }

    private func parseHRData(_ data: Data) {
        guard let bpm = data.first else { return }
        DispatchQueue.main.async {
            self.heartRate = Double(bpm)
        }
    }
}
