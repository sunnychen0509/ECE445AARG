import CoreBluetooth
import SwiftUI

class BLEImageReceiver: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // BLE properties
    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?  // Single characteristic for read/write

    // Image data accumulation
    @Published var receivedImage: UIImage?
    private var imageDataBuffer = Data()
    
    // UUID definitions – update these strings to exactly match your firmware definitions.
    private let serviceUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef0")
    private let characteristicUUID = CBUUID(string: "abcdef01-1234-5678-1234-56789abcdef0")
    
    // Track connection status
    @Published var isConnected = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    // MARK: - CBCentralManagerDelegate Methods
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is ON. Scanning for ESP32...")
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        case .unauthorized:
            print("Bluetooth unauthorized. Verify Info.plist permissions.")
        case .unsupported:
            print("This device does not support BLE.")
        case .poweredOff:
            print("Bluetooth is turned off. Enable it in Settings.")
        default:
            print("Unknown Bluetooth state: \(central.state.rawValue)")
        }
    }
    
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        // Connect to the first peripheral found
        esp32Peripheral = peripheral
        centralManager.stopScan()
        print("Discovered peripheral: \(peripheral.name ?? "Unknown")")
        esp32Peripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
    }
    
    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        isConnected = true
        peripheral.discoverServices([serviceUUID])
    }
    
    // MARK: - CBPeripheralDelegate Methods
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            print("Discovered service: \(service.uuid.uuidString)")
            // Discover the single read/write characteristic.
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                dataCharacteristic = characteristic
                print("Characteristic discovered and notifications enabled.")
                // Enable notifications for incoming data
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    // Called when new data comes in from the ESP32.
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let chunk = characteristic.value else { return }

        // Check if the chunk is "EOF" string
        if let text = String(data: chunk, encoding: .utf8), text == "EOF" {
            print("EOF received. Processing image...")

            if let image = UIImage(data: imageDataBuffer) {
                DispatchQueue.main.async {
                    self.receivedImage = image
                }
                print("Image updated in UI.")
            } else {
                print("Error: Unable to decode image data.")
            }

            imageDataBuffer.removeAll()
        } else {
            imageDataBuffer.append(chunk)
        }
    }
    
    // Public function to send the "img_capture" command to the ESP32.
    func sendCaptureCommand() {
        guard let peripheral = esp32Peripheral,
              let characteristic = dataCharacteristic else {
            print("Peripheral or characteristic not available. Cannot send command.")
            return
        }
        let command = "img_capture"
        guard let commandData = command.data(using: .utf8) else {
            print("Error: Unable to convert command to data.")
            return
        }
        peripheral.writeValue(commandData, for: characteristic, type: .withResponse)
        print("Sent command: \(command)")
    }
}
