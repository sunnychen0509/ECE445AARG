import CoreBluetooth
import SwiftUI

class BLEImageReceiver: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var centralManager: CBCentralManager!
    var discoveredPeripheral: CBPeripheral?
    var imageCharacteristic: CBCharacteristic?

    @Published var receivedImage: UIImage?
    var imageDataBuffer = Data()

    let imageServiceUUID = CBUUID(string: "12345678-1234-1234-1234-123456789abc")
    let imageCharacteristicUUID = CBUUID(string: "abcd1234-5678-90ab-cdef-123456789abc")

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            centralManager.scanForPeripherals(withServices: [imageServiceUUID], options: nil)
        } else {
            print("Bluetooth unavailable.")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any], rssi RSSI: NSNumber) {
        discoveredPeripheral = peripheral
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([imageServiceUUID])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            if service.uuid == imageServiceUUID {
                peripheral.discoverCharacteristics([imageCharacteristicUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == imageCharacteristicUUID {
                imageCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
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

