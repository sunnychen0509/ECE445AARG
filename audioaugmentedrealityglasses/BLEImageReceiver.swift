import CoreBluetooth
import SwiftUI
import AVFoundation

class BLEImageReceiver: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var centralManager: CBCentralManager!
    private var esp32Peripheral: CBPeripheral?
    private var dataCharacteristic: CBCharacteristic?

    @Published var receivedImage: UIImage?
    @Published var wavEOFsent = false
    @Published var isConnected = false
    @Published var buttonPressed = false

    private var imageDataBuffer = Data()

    private let serviceUUID = CBUUID(string: "12345678-1234-5678-1234-56789abcdef1") // 0 for devkit, 1 for main esp32
    private let characteristicUUID = CBUUID(string: "abcdef01-1234-5678-1234-56789abcdef1")

    private let expectedSampleRate: Double = 8000
    private let expectedChannels: AVAudioChannelCount = 1
    private let expectedBitsPerSample: UInt32 = 16

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("Bluetooth is ON. Scanning for ESP32...")
            centralManager.scanForPeripherals(withServices: [serviceUUID], options: nil)
        } else {
            print("Bluetooth state changed to \(central.state.rawValue)")
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
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

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([characteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == characteristicUUID {
            dataCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
            print("Characteristic discovered and notifications enabled.")
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let chunk = characteristic.value else { return }

        if let text = String(data: chunk, encoding: .utf8), text == "act_button" {
            if GlobalFlowManager.shared.isBusy {
                print("🔴 Ignoring GPIO button press because user flow is active.")
                return
            }
            print("GPIO button pressed on ESP32")
            imageDataBuffer.removeAll()
            sendCommand("img_capture")
            DispatchQueue.main.async {
                self.buttonPressed.toggle()
            }
            return
        }

        if let text = String(data: chunk, encoding: .utf8), text == "EOF" {
            print("EOF received. Processing image...")
            if let image = UIImage(data: imageDataBuffer) {
                DispatchQueue.main.async { self.receivedImage = image }
                print("Image updated in UI.")
            } else {
                print("Error: Unable to decode image data.")
                GlobalFlowManager.shared.isBusy = false
            }
            imageDataBuffer.removeAll()
        } else {
            imageDataBuffer.append(chunk)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.uuid == characteristicUUID else { return }
        if let err = error {
            print("Error writing to characteristic: \(err.localizedDescription)")
        } else {
            if wavEOFsent {
                print("EOF marker WRITE CONFIRMED by peripheral callback")
                wavEOFsent = false
            } else {
                print("Data chunk WRITE CONFIRMED")
            }
        }
    }

    // MARK: - Commands

    func sendCommand(_ command: String) {
        guard let peripheral = esp32Peripheral,
              let characteristic = dataCharacteristic,
              let data = command.data(using: .utf8) else {
            print("Peripheral/characteristic unavailable or command conversion failed.")
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        print("Sent command: \(command)")
    }


    // MARK: - WAV Streaming Utilities

    private func readWAVMetadata(from url: URL) -> (sampleRate: Double,
                                                   channels: AVAudioChannelCount,
                                                   bitsPerSample: UInt32)? {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let desc = audioFile.fileFormat.streamDescription.pointee
            return (format.sampleRate, format.channelCount, desc.mBitsPerChannel)
        } catch {
            print("Failed to read WAV metadata: \(error)")
            return nil
        }
    }

    func sendRawPCMChunks(from wavURL: URL) async {
        guard let peripheral = esp32Peripheral,
              let characteristic = dataCharacteristic else {
            print("Peripheral or characteristic not ready for PCM streaming.")
            return
        }

        if let meta = readWAVMetadata(from: wavURL) {
            guard meta.sampleRate == expectedSampleRate,
                  meta.channels == expectedChannels,
                  meta.bitsPerSample == expectedBitsPerSample else {
                print("WAV metadata mismatch! Expected: \(expectedSampleRate)Hz, \(expectedChannels)ch, \(expectedBitsPerSample)-bit")
                return
            }
        } else {
            print("Unable to verify WAV metadata, aborting PCM stream.")
            return
        }

        do {
            let wavData = try Data(contentsOf: wavURL)
            let headerSize = 44
            guard wavData.count > headerSize else {
                print("WAV file too small to contain header and data!")
                return
            }
            let pcmData = wavData.subdata(in: headerSize..<wavData.count)

            let chunkSize = 500
            var offset = 0
            print("🔈 Streaming RAW PCM (\(pcmData.count) bytes) in \(pcmData.count / chunkSize + 1) chunks…")

            while offset < pcmData.count {
                let end = min(offset + chunkSize, pcmData.count)
                let chunk16 = pcmData.subdata(in: offset..<end)

                let chunk8 = downsample16to8bit(pcm16: chunk16)

                peripheral.writeValue(chunk8, for: characteristic, type: .withoutResponse)

                offset = end
                usleep(2_000)
                await Task.yield()
            }

            if let eofData = "EOF".data(using: .utf8) {
                wavEOFsent = true
                peripheral.writeValue(eofData, for: characteristic, type: .withResponse)
                print("Sent EOF marker for PCM stream (awaiting confirmation)…")
            }
        } catch {
            print("Failed to load WAV for PCM extraction: \(error)")
        }
    }

    func downsample16to8bit(pcm16: Data) -> Data {
        var pcm8 = Data(capacity: pcm16.count / 2)
        let sampleCount = pcm16.count / 2

        pcm16.withUnsafeBytes { (src: UnsafeRawBufferPointer) in
            let srcPtr = src.bindMemory(to: Int16.self)

            for i in 0..<sampleCount {
                let s16 = Int(srcPtr[i])
                let s8 = UInt8(clamping: (s16 / 256) + 128)
                pcm8.append(s8)
            }
        }
        return pcm8
    }
}
