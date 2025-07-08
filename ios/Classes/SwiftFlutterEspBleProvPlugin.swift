import Flutter
import UIKit
import ESPProvision
import CoreBluetooth

typealias CustomDataTuple = (path: String, value: String)

public class SwiftFlutterEspBleProvPlugin: NSObject, FlutterPlugin {
    private let SCAN_BLE_DEVICES = "scanBleDevices"
    private let SCAN_WIFI_NETWORKS = "scanWifiNetworks"
    private let PROVISION_WIFI = "provisionWifi"

    private let ARG_DEVICE_NAME = "deviceName"
    private let ARG_POP = "proofOfPossession"
    private let ARG_SSID = "ssid"
    private let ARG_PASSPHRASE = "passphrase"
    private let ARG_PROV_TOKEN = "prov_token"
    private let ARG_THING_ID = "thing_id"
    private let ARG_CLAIM_CERT = "claim_cert"
    private let ARG_CLAIM_KEY = "claim_key"
    private let ARG_CA_CERT = "ca_cert"
    private let ARG_MQTT_URL = "mqtt_url"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_esp_ble_prov", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterEspBleProvPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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

            let provToken = arguments[ARG_PROV_TOKEN] as? String ?? ""
            let thingId = arguments[ARG_THING_ID] as? String ?? ""
            let claimCert = arguments[ARG_CLAIM_CERT] as? String ?? ""
            let claimKey = arguments[ARG_CLAIM_KEY] as? String ?? ""
            let caCert = arguments[ARG_CA_CERT] as? String ?? ""
            let mqttUrl = arguments[ARG_MQTT_URL] as? String ?? ""

            var customDataList: [CustomDataTuple] = []
            if !provToken.isEmpty { customDataList.append(("prov_token", provToken)) }
            if !thingId.isEmpty { customDataList.append(("thing_id", thingId)) }
            if !claimCert.isEmpty { customDataList.append(("claim_cert", claimCert)) }
            if !claimKey.isEmpty { customDataList.append(("claim_key", claimKey)) }
            if !caCert.isEmpty { customDataList.append(("ca_cert", caCert)) }
            if !mqttUrl.isEmpty { customDataList.append(("mqtt_url", mqttUrl)) }

            provisionService.provision(
                deviceName: deviceName,
                proofOfPossession: pop,
                ssid: ssid,
                passphrase: passphrase,
                customDataList: customDataList
            )

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

private class BLEProvisionService {
    var result: FlutterResult
    let defaultMtu = 180

    init(result: @escaping FlutterResult) {
        self.result = result
    }

    func searchDevices(prefix: String) {
        ESPProvisionManager.shared.searchESPDevices(devicePrefix: prefix, transport: .ble, security: .secure) { deviceList, error in
            if let error = error {
                ESPErrorHandler.handle(error: error, result: self.result)
            } else {
                self.result(deviceList?.map { $0.name })
            }
        }
    }

    func scanWifiNetworks(deviceName: String, proofOfPossession: String) {
        connect(deviceName: deviceName, proofOfPossession: proofOfPossession) { device in
            device?.scanWifiList { wifiList, error in
                if let error = error {
                    ESPErrorHandler.handle(error: error, result: self.result)
                } else {
                    self.result(wifiList?.map { $0.ssid })
                }
            }
        }
    }

    func provision(deviceName: String, proofOfPossession: String, ssid: String, passphrase: String, customDataList: [CustomDataTuple]) {
        connect(deviceName: deviceName, proofOfPossession: proofOfPossession) { device in
            guard let espDevice = device else { return }

            func startProvision() {
                espDevice.provision(ssid: ssid, passPhrase: passphrase) { status in
                    switch status {
                    case .success:
                        self.result(true)
                    case .failure:
                        self.result(false)
                    default:
                        NSLog("Provision status: \(status)")
                        self.result(false)
                    }
                }
            }

            if customDataList.isEmpty {
                startProvision()
            } else {
                self.sendCustomDataSequentially(device: espDevice, dataList: customDataList, currentIndex: 0) { _ in
                    startProvision()
                }
            }
        }
    }

    func connect(deviceName: String, proofOfPossession: String, completion: @escaping (ESPDevice?) -> Void) {
        ESPProvisionManager.shared.createESPDevice(deviceName: deviceName, transport: .ble, security: .secure, proofOfPossession: proofOfPossession) { device, error in
            guard let device = device else {
                let err = NSError(domain: "ESP", code: 100, userInfo: [NSLocalizedDescriptionKey: "Could not create device"])
                ESPErrorHandler.handle(error: err, result: self.result)
                completion(nil)
                return
            }

            device.connect { status in
                switch status {
                case .connected:
                    completion(device)
                case .failedToConnect, .disconnected:
                    let err = NSError(domain: "ESP", code: 101, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to device"])
                    ESPErrorHandler.handle(error: err, result: self.result)
                    completion(nil)
                default:
                    completion(nil)
                }
            }
        }
    }

    func sendCustomDataSequentially(device: ESPDevice, dataList: [CustomDataTuple], currentIndex: Int, completion: @escaping (Bool) -> Void) {
        if currentIndex >= dataList.count {
            completion(true)
            return
        }

        let item = dataList[currentIndex]
        guard let data = item.value.data(using: .utf8) else {
            sendCustomDataSequentially(device: device, dataList: dataList, currentIndex: currentIndex + 1, completion: completion)
            return
        }

        sendDataInChunks(device: device, path: item.path, data: data, mtu: defaultMtu) { _ in
            self.sendCustomDataSequentially(device: device, dataList: dataList, currentIndex: currentIndex + 1, completion: completion)
        }
    }

    func sendDataInChunks(device: ESPDevice, path: String, data: Data, mtu: Int, completion: @escaping (Error?) -> Void) {
        let dataLength = data.count
        var offset = 0

        func sendNextChunk() {
            if offset >= dataLength {
                completion(nil)
                return
            }

            let chunkSize = min(mtu, dataLength - offset)
            let chunk = data.subdata(in: offset ..< offset + chunkSize)

            device.sendData(path: path, data: chunk) { _, error in
                if let error = error {
                    completion(error)
                } else {
                    offset += chunkSize
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        sendNextChunk()
                    }
                }
            }
        }

        sendNextChunk()
    }
}

private class ESPErrorHandler {
    static func handle(error: Error, result: FlutterResult) {
        result(FlutterError(code: "ESP_ERROR", message: error.localizedDescription, details: nil))
    }
}