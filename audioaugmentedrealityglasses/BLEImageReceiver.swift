import CoreBluetooth
import SwiftUI

class BLEImageReceiver: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    var discoveredPeripheral: CBPeripheral?
    var imageCharacteristic: CBCharacteristic?
    var commandCharacteristic: CBCharacteristic?  // New for sending request

    @Published var receivedImage: UIImage?
    var imageDataBuffer = Data()

    // UUIDs
    let imageServiceUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef0")
    let imageCharacteristicUUID = CBUUID(string: "abcdef01-1234-5678-1234-56789abcdef0")
    let commandCharacteristicUUID = CBUUID(string: "87654321-4321-4321-4321-cba987654321") // Your custom UUID

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // 1. Scan for peripherals
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is ON. Scanning now...")
            centralManager.scanForPeripherals(withServices: [imageServiceUUID], options: nil)
        case .unauthorized:
            print("Bluetooth unauthorized. Check Info.plist.")
        case .unsupported:
            print("Device does not support BLE.")
        case .poweredOff:
            print("Bluetooth is off. Please enable it in settings.")
        default:
            print("Unknown Bluetooth state: \(central.state.rawValue)")
        }
    }

    // 2. Discover & connect
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discoveredPeripheral = peripheral
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    // 3. Connected, discover services
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([imageServiceUUID])
    }

    // 4. Services discovered
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == imageServiceUUID {
                // Discover BOTH characteristics
                peripheral.discoverCharacteristics([imageCharacteristicUUID, commandCharacteristicUUID], for: service)
            }
        }
    }

    // 5. Characteristics discovered
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.uuid == imageCharacteristicUUID {
                imageCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            } else if characteristic.uuid == commandCharacteristicUUID {
                commandCharacteristic = characteristic
                sendCaptureCommand()  // 🟡 Send request after discovering command characteristic
            }
        }
    }

    // 6. Send "CAPTURE" command to ESP32
    func sendCaptureCommand() {
        guard let peripheral = discoveredPeripheral,
              let commandChar = commandCharacteristic else {
            print("Command characteristic or peripheral unavailable")
            return
        }

        let command = "CAPTURE"
        if let data = command.data(using: .utf8) {
            peripheral.writeValue(data, for: commandChar, type: .withResponse)
            print("Sent capture command to ESP32.")
        }
    }

    // 7. Receive image chunks
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value else { return }
        imageDataBuffer.append(data)

        if imageDataBuffer.suffix(2) == Data([0xFF, 0xD9]) {
            if let image = UIImage(data: imageDataBuffer) {
                DispatchQueue.main.async {
                    self.receivedImage = image
                }
            } else {
                print("Failed to convert to image")
            }
            imageDataBuffer.removeAll()
        }
    }
}
