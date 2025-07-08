swift
import Flutter
import UIKit
import ESPProvision // Assuming this is your ESP provisioning library
import CoreBluetooth // Needed for MTU considerations, though ESPProvision might abstract it

// Define a simple type alias for clarity if you pass around data tuples often
typealias CustomDataTuple = (path: String, value: String)

public class SwiftFlutterEspBleProvPlugin: NSObject, FlutterPlugin {
    private let SCAN_BLE_DEVICES = "scanBleDevices"
    private let SCAN_WIFI_NETWORKS = "scanWifiNetworks"
    private let PROVISION_WIFI = "provisionWifi"
    // It's good practice to define constants for argument keys
    private let ARG_DEVICE_NAME = "deviceName"
    private let ARG_POP = "proofOfPossession"
    private let ARG_SSID = "ssid"
    private let ARG_PASSPHRASE = "passphrase"
    private let ARG_PROV_TOKEN = "prov_token"
    private let ARG_THING_ID = "thing_id"
    private let ARG_CLAIM_CERT = "claim_cert"
    private let ARG_CLAIM_KEY = "claim_key"
    private let ARG_CA_CERT = "ca_cert"
    private let ARG_MQTT_URL = "mqtt_url" // Corrected key from "mqtt_url "

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_esp_ble_prov", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterEspBleProvPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        // It's safer to cast arguments and handle potential nil values
        guard let arguments = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Arguments are not a dictionary", details: nil))
            return
        }

        let provisionService = BLEProvisionService(result: result)

        switch call.method {
        case SCAN_BLE_DEVICES:
            guard let prefix = arguments["prefix"] as? String else {
                result(FlutterError(code: "MISSING_ARGUMENT", message: "Missing 'prefix' argument", details: nil))
                return
            }
            provisionService.searchDevices(prefix: prefix)
        case SCAN_WIFI_NETWORKS:
            guard let deviceName = arguments[ARG_DEVICE_NAME] as? String,
                  let pop = arguments[ARG_POP] as? String else {
                result(FlutterError(code: "MISSING_ARGUMENT", message: "Missing 'deviceName' or 'proofOfPossession'", details: nil))
                return
            }
            provisionService.scanWifiNetworks(deviceName: deviceName, proofOfPossession: pop)
        case PROVISION_WIFI:
            guard let deviceName = arguments[ARG_DEVICE_NAME] as? String,
                  let pop = arguments[ARG_POP] as? String,
                  let ssid = arguments[ARG_SSID] as? String,
                  let passphrase = arguments[ARG_PASSPHRASE] as? String else {
                result(FlutterError(code: "MISSING_ARGUMENT", message: "Missing required arguments for provisioning", details: nil))
                return
            }

            // Extract all custom data fields, providing empty strings as defaults if not present
            // This mirrors the Android takeIf { it.isNotEmpty() } logic implicitly
            let provToken = arguments[ARG_PROV_TOKEN] as? String ?? ""
            let thingId = arguments[ARG_THING_ID] as? String ?? ""
            let claimCert = arguments[ARG_CLAIM_CERT] as? String ?? ""
            let claimKey = arguments[ARG_CLAIM_KEY] as? String ?? ""
            let caCert = arguments[ARG_CA_CERT] as? String ?? ""
            let mqttUrl = arguments[ARG_MQTT_URL] as? String ?? "" // Corrected key

            // Create a list of tuples (path, value) for data to send, filtering out empty values
            var customDataList: [CustomDataTuple] = []
            if !provToken.isEmpty { customDataList.append((path: "prov_token", value: provToken)) }
            if !thingId.isEmpty { customDataList.append((path: "thing_id", value: thingId)) }
            if !claimCert.isEmpty { customDataList.append((path: "claim_cert", value: claimCert)) }
            if !claimKey.isEmpty { customDataList.append((path: "claim_key", value: claimKey)) }
            if !caCert.isEmpty { customDataList.append((path: "ca_cert", value: caCert)) }
            if !mqttUrl.isEmpty { customDataList.append((path: "mqtt_url", value: mqttUrl)) }

            provisionService.provision(
                deviceName: deviceName,
                proofOfPossession: pop,
                ssid: ssid,
                passphrase: passphrase,
                customDataList: customDataList // Pass the list
            )
        default:
            result(FlutterMethodNotImplemented) // More standard than sending iOS version for unimplemented
        }
    }
}

protocol ProvisionService {
    var result: FlutterResult { get }
    func searchDevices(prefix: String)
    func scanWifiNetworks(deviceName: String, proofOfPossession: String)
    // Updated provision method signature
    func provision(deviceName: String, proofOfPossession: String, ssid: String, passphrase: String, customDataList: [CustomDataTuple])
}

private class BLEProvisionService: ProvisionService {
    var result: FlutterResult

    // Default MTU size, similar to Android.
    // This might need adjustment based on the ESPDevice's actual MTU negotiation.
    // The ESPProvision library might handle MTU internally, or you might get it from the CBPeripheral.
    let defaultMtu = 180 // Max bytes per chunk (data part, excluding BLE headers)

    init(result: @escaping FlutterResult) {
        self.result = result
    }

    func searchDevices(prefix: String) {
        ESPProvisionManager.shared.searchESPDevices(devicePrefix: prefix, transport: .ble, security: .secure) { deviceList, error in
            if let error = error {
                NSLog("Error searchDevices: \(error.localizedDescription)")
                ESPErrorHandler.handle(error: error, result: self.result)
            } else {
                self.result(deviceList?.map { $0.name })
            }
        }
    }

    func scanWifiNetworks(deviceName: String, proofOfPossession: String) {
        self.connect(deviceName: deviceName, proofOfPossession: proofOfPossession) { device in
            guard let espDevice = device else {
                // Connection already handled error in connect or reported success
                return
            }
            espDevice.scanWifiList { wifiList, error in
                if let error = error {
                    NSLog("Error scanning wifi networks, deviceName: \(deviceName), error: \(error.localizedDescription)")
                    ESPErrorHandler.handle(error: error, result: self.result)
                } else {
                    self.result(wifiList?.map { $0.ssid })
                }
                // It's often good practice to disconnect after the operation is complete
                // espDevice.disconnect() // Or manage connection lifecycle as needed
            }
        }
    }

    // Updated provision method
    func provision(deviceName: String, proofOfPossession: String, ssid: String, passphrase: String, customDataList: [CustomDataTuple]) {
        self.connect(deviceName: deviceName, proofOfPossession: proofOfPossession) { device in
            guard let espDevice = device else {
                // Connection failure already handled in connect
                return
            }

            if customDataList.isEmpty {
                NSLog("No custom data to send. Starting WiFi provisioning directly.")
                self.startWifiProvisioning(device: espDevice, ssid: ssid, passphrase: passphrase)
            } else {
                NSLog("Starting to send custom data items: \(customDataList.count)")
                self.sendCustomDataSequentially(
                    device: espDevice,
                    dataList: customDataList,
                    currentIndex: 0
                ) { allSentSuccessfully in // Completion for sending all custom data
                    if allSentSuccessfully {
                        NSLog("All custom data sent successfully. Starting WiFi provisioning.")
                    } else {
                        NSLog("Some custom data failed to send. Proceeding with WiFi provisioning anyway.")
                        // You might decide to fail here if any custom data send is critical
                    }
                    self.startWifiProvisioning(device: espDevice, ssid: ssid, passphrase: passphrase)
                }
            }
        }
    }

    private func sendCustomDataSequentially(
        device: ESPDevice,
        dataList: [CustomDataTuple],
        currentIndex: Int,
        completion: @escaping (Bool) -> Void // True if all successful, false otherwise
    ) {
        if currentIndex >= dataList.count {
            NSLog("All custom data items processed.")
            completion(true) // Indicate all items were attempted
            return
        }

        let currentItem = dataList[currentIndex]
        let endpointPath = currentItem.path
        guard let dataToSend = currentItem.value.data(using: .utf8) else {
            NSLog("Error: Could not convert string to Data for path \(endpointPath)")
            // Continue with the next item, marking this one as a failure implicitly
            self.sendCustomDataSequentially(device: device, dataList: dataList, currentIndex: currentIndex + 1, completion: completion)
            return
        }

        NSLog("Sending data for endpoint: \(endpointPath), data size: \(dataToSend.count) bytes")

        // Get the actual MTU for the connected peripheral if possible and if ESPDevice exposes it.
        // For now, using defaultMtu. The ESPProvision library might handle this.
        // If device.peripheral is accessible and is a CBPeripheral:
        // let mtu = device.peripheral?.maximumWriteValueLength(for: .withResponse) ?? defaultMtu
        let mtu = defaultMtu // Use the default or a value from the device if available

        sendDataInChunks(device: device, path: endpointPath, data: dataToSend, mtu: mtu) { error in
            if let error = error {
                NSLog("Error sending data for endpoint \(endpointPath): \(error.localizedDescription)")
                // Decide if you want to stop or continue on error for a single item
                // For now, we continue and the overall success will be marked by the completion handler's parameter
            } else {
                NSLog("Successfully sent all chunks for endpoint: \(endpointPath)")
            }
            // Send the next item
            self.sendCustomDataSequentially(device: device, dataList: dataList, currentIndex: currentIndex + 1, completion: completion)
        }
    }

    private func sendDataInChunks(
        device: ESPDevice,
        path: String,
        data: Data,
        mtu: Int, // Max data payload size per write
        completion: @escaping (Error?) -> Void
    ) {
        let dataLength = data.count
        var offset = 0

        // Inner function to send the next chunk
        func sendNextChunk() {
            if offset >= dataLength {
                NSLog("All chunks sent for path: \(path)")
                completion(nil) // All done, no error
                return
            }

            let chunkSize = min(mtu, dataLength - offset)
            let chunk = data.subdata(in: offset ..< offset + chunkSize)

            NSLog("Sending chunk for path '\(path)': offset \(offset), size \(chunk.count) bytes")

            // The ESPDevice.sendData method should handle the BLE write
            // The path parameter in ESPDevice.sendData is the GATT characteristic endpoint
            device.sendData(path: path, data: chunk) { responseData, error in
                if let error = error {
                    NSLog("Error sending chunk for path '\(path)' at offset \(offset): \(error.localizedDescription)")
                    completion(error) // Report error and stop
                    return
                }

                // Log response if any (optional)
                if let responseData = responseData, let responseStr = String(data: responseData, encoding: .utf8) {
                    NSLog("Response for chunk at path '\(path)', offset \(offset): \(responseStr)")
                } else if responseData != nil {
                    NSLog("Response for chunk at path '\(path)', offset \(offset) was non-UTF8 data.")
                }

                offset += chunkSize
                // Introduce a small delay if needed, especially if the peripheral requires time between writes
                // DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { // e.g., 50ms delay
                sendNextChunk()
                // }
            }
        }
        sendNextChunk() // Start sending the first chunk
    }

    private func startWifiProvisioning(device: ESPDevice, ssid: String, passphrase: String) {
        NSLog("Starting WiFi provisioning with SSID: \(ssid)")
        device.provision(ssid: ssid, passPhrase: passphrase) { status, error in // ESPProvision 2.x often includes error in the callback
            if let error = error { // Handle potential error from the provision call itself
                NSLog("Provisioning error: \(error.localizedDescription)")
                ESPErrorHandler.handle(error: error, result: self.result) // Use your ESPError or a generic FlutterError
                return
            }

            // Handle status based on ESPProvision library version
            switch status {
            case .success: // Or .provisioned, .applied, etc. depending on library
                NSLog("Device provisioning success for SSID: \(ssid)")
                self.result(true)
            case .configApplied: // Example status
                NSLog("WiFi config applied for SSID: \(ssid)")
                // Often, you wait for .success or handle this as an intermediate step
            case .failure: // Or .failed, .error
                NSLog("WiFi provisioning failed for SSID: \(ssid)")
                self.result(false) // Or provide more detailed error
                // Add other cases as defined by your ESPProvision library's ESPStatus enum
            default:
                NSLog("WiFi provisioning status: \(status) for SSID: \(ssid)")
                // self.result(nil) or handle appropriately
            }
        }
    }

    private func connect(deviceName: String, proofOfPossession: String, completionHandler: @escaping (ESPDevice?) -> Void) {
        NSLog("Attempting to connect to device: \(deviceName)")
        ESPProvisionManager.shared.createESPDevice(
            deviceName: deviceName,
            transport: .ble,
            security: .secure, // Assuming security .secure, adjust if using .unsecure
            proofOfPossession: proofOfPossession
        ) { espDevice, error in
            if let error = error {
                NSLog("Error creating ESPDevice \(deviceName): \(error.localizedDescription)")
                ESPErrorHandler.handle(error: error, result: self.result)
                completionHandler(nil)
                return
            }

            guard let device = espDevice else {
                NSLog("Failed to create ESPDevice instance for \(deviceName), espDevice is nil.")
                self.result(FlutterError(code: "DEVICE_CREATION_FAILED", message: "ESPDevice instance is nil after creation.", details: nil))
                completionHandler(nil)
                return
            }

            device.connect { status, error in // ESPProvision 2.x often includes error in connect callback
                if let error = error { // Handle error from the connect call itself
                    NSLog("Connection error for device \(deviceName): \(error.localizedDescription)")
                    ESPErrorHandler.handle(error: error, result: self.result)
                    completionHandler(nil)
                    return
                }

                // Handle status based on ESPProvision library version
                switch status {
                case .connected:
                    NSLog("Successfully connected to device: \(deviceName)")
                    completionHandler(device)
                case .failedToConnect: // This case might be covered by the error parameter now
                    NSLog("Failed to connect to device: \(deviceName)")
                    // The error parameter in the callback should provide more details.
                    // If ESPError is not available, construct a FlutterError.
                    let connectError = ESPError(code: 101, description: "Failed to connect to BLE device") // Example error
                    ESPErrorHandler.handle(error: connectError, result: self.result)
                    completionHandler(nil)
                case .disconnected: // Handle if disconnect is a status during connection attempt
                    NSLog("Device \(deviceName) disconnected during connection attempt.")
                    let disconnectError = ESPError(code: 102, description: "Device disconnected during connection attempt")
                    ESPErrorHandler.handle(error: disconnectError, result: self.result)
                    completionHandler(nil)
                    // Add other relevant cases from ESPDeviceConnectionEvent or similar enum
                default:
                    NSLog("Connection status for device \(deviceName): \(status)")
                    // Potentially an unexpected state
                    let unknownError = ESPError(code: 103, description: "Unknown connection status: \(status)")
                    ESPErrorHandler.handle(error: unknownError, result: self.result)
                    completionHandler(nil)
                }
            }
        }
    }
}

// Ensure ESPErrorHandler can handle generic Error or specific ESPError
private class ESPErrorHandler {
    static func handle(error: Error, result: FlutterResult) { // Changed to accept generic Error
        if let espError = error as? ESPError {
            result(FlutterError(code: String(espError.code), message: espError.description, details: espError.localizedDescription))
        } else {
            // For other types of errors, provide a generic error code/message
            result(FlutterError(code: "NATIVE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
}