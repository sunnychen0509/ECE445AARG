import CoreBluetooth
import SwiftUI

class BLEImageReceiver: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?

    @Published var receivedImage: UIImage?
    private var imageDataBuffer = Data()

    private let serviceUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef0")
    private let characteristicUUID = CBUUID(string: "abcdef01-1234-5678-1234-56789abcdef0")

    @Published var isConnected = false

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

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

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        esp32Peripheral = peripheral
        centralManager.stopScan()
        print("Discovered peripheral: \(peripheral.name ?? "Unknown")")
        esp32Peripheral?.delegate = self
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected to peripheral: \(peripheral.name ?? "Unknown")")
        isConnected = true
        peripheral.discoverServices([serviceUUID])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            print("Discovered service: \(service.uuid.uuidString)")
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                dataCharacteristic = characteristic
                print("Characteristic discovered and notifications enabled.")
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let chunk = characteristic.value else { return }

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
    
    func sendCommand(_ command: String) {
        guard let peripheral = esp32Peripheral,
              let characteristic = dataCharacteristic,
              let commandData = command.data(using: .utf8) else {
            print("Peripheral/characteristic unavailable or command conversion failed.")
            return
        }
        peripheral.writeValue(commandData, for: characteristic, type: .withResponse)
        print("Sent command: \(command)")
    }

    func sendMP3FileChunks(fileURL: URL) {
        guard let peripheral = esp32Peripheral,
              let characteristic = dataCharacteristic else {
            print("Peripheral or characteristic not ready for MP3 streaming.")
            return
        }

        do {
            let mp3Data = try Data(contentsOf: fileURL)
            let chunkSize = 180
            var offset = 0

            print("Sending MP3 in \(mp3Data.count / chunkSize + 1) chunks...")
            while offset < mp3Data.count {
                let end = min(offset + chunkSize, mp3Data.count)
                let chunk = mp3Data.subdata(in: offset..<end)
                peripheral.writeValue(chunk, for: characteristic, type: .withResponse)
                offset = end
                usleep(10_000)
            }
            if let eofData = "EOF".data(using: .utf8) {
                peripheral.writeValue(eofData, for: characteristic, type: .withResponse)
                print("Sent EOF to ESP32")
            }
        } catch {
            print("Error reading MP3 file: \(error.localizedDescription)")
        }
    }
}
