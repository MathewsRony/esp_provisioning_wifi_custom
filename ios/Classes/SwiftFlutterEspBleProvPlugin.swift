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
        let channel = FlutterMethodChannel(name: "flutter_esp_ble_prov",
                                           binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterEspBleProvPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Arguments not a dict", details: nil))
            return
        }

        let service = BLEProvisionService(result: result)

        switch call.method {
        case SCAN_BLE_DEVICES:
            guard let prefix = args["prefix"] as? String else {
                result(FlutterError(code: "MISSING_ARG", message: "Missing prefix", details: nil))
                return
            }
            service.searchDevices(prefix: prefix)

        case SCAN_WIFI_NETWORKS:
            guard let dev = args[ARG_DEVICE_NAME] as? String,
                  let pop = args[ARG_POP] as? String else {
                result(FlutterError(code: "MISSING_ARG", message: "Missing deviceName or pop", details: nil))
                return
            }
            service.scanWifiNetworks(deviceName: dev, proofOfPossession: pop)

        case PROVISION_WIFI:
            guard let dev = args[ARG_DEVICE_NAME] as? String,
                  let pop = args[ARG_POP] as? String,
                  let ssid = args[ARG_SSID] as? String,
                  let pass = args[ARG_PASSPHRASE] as? String else {
                result(FlutterError(code: "MISSING_ARG", message: "Missing required args", details: nil))
                return
            }

            let token = args[ARG_PROV_TOKEN] as? String ?? ""
            let thingId = args[ARG_THING_ID] as? String ?? ""
            let cert = args[ARG_CLAIM_CERT] as? String ?? ""
            let key = args[ARG_CLAIM_KEY] as? String ?? ""
            let ca = args[ARG_CA_CERT] as? String ?? ""
            let mqtt = args[ARG_MQTT_URL] as? String ?? ""

            var list: [CustomDataTuple] = []
            if !token.isEmpty { list.append(("prov_token", token)) }
            if !thingId.isEmpty { list.append(("thing_id", thingId)) }
            if !cert.isEmpty { list.append(("claim_cert", cert)) }
            if !key.isEmpty { list.append(("claim_key", key)) }
            if !ca.isEmpty { list.append(("ca_cert", ca)) }
            if !mqtt.isEmpty { list.append(("mqtt_url", mqtt)) }

            service.provision(deviceName: dev,
                              proofOfPossession: pop,
                              ssid: ssid,
                              passphrase: pass,
                              customDataList: list)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

protocol ProvisionService {
    var result: FlutterResult { get }
    func searchDevices(prefix: String)
    func scanWifiNetworks(deviceName: String, proofOfPossession: String)
    func provision(deviceName: String,
                   proofOfPossession: String,
                   ssid: String,
                   passphrase: String,
                   customDataList: [CustomDataTuple])
}

private class BLEProvisionService: ProvisionService {
    var result: FlutterResult
    let defaultMtu = 180

    init(result: @escaping FlutterResult) {
        self.result = result
    }

    func searchDevices(prefix: String) {
        ESPProvisionManager.shared.searchESPDevices(devicePrefix: prefix,
                                                    transport: .ble,
                                                    security: .secure) { devs, err in
            if let err = err {
                ESPErrorHandler.handle(error: err, result: self.result)
            } else {
                self.result(devs?.map { $0.name })
            }
        }
    }

    func scanWifiNetworks(deviceName: String, proofOfPossession: String) {
        connect(deviceName: deviceName, proofOfPossession: proofOfPossession) { device in
            guard let d = device else { return }
            d.scanWifiList { list, err in
                if let err = err {
                    ESPErrorHandler.handle(error: err, result: self.result)
                } else {
                    self.result(list?.map { $0.ssid })
                }
            }
        }
    }

    func provision(deviceName: String,
                   proofOfPossession: String,
                   ssid: String,
                   passphrase: String,
                   customDataList: [CustomDataTuple]) {
        connect(deviceName: deviceName, proofOfPossession: proofOfPossession) { device in
            guard let dev = device else { return }

            if customDataList.isEmpty {
                self.startWifiProvisioning(device: dev, ssid: ssid, passphrase: passphrase)
            } else {
                self.sendCustomDataSequentially(device: dev,
                                                dataList: customDataList,
                                                currentIndex: 0) { _ in
                    self.startWifiProvisioning(device: dev, ssid: ssid, passphrase: passphrase)
                }
            }
        }
    }

    private func sendCustomDataSequentially(device: ESPDevice,
                                            dataList: [CustomDataTuple],
                                            currentIndex: Int,
                                            completion: @escaping (Bool) -> Void) {
        if currentIndex >= dataList.count {
            completion(true); return
        }

        let item = dataList[currentIndex]
        guard let bytes = item.value.data(using: .utf8) else {
            sendCustomDataSequentially(device: device, dataList: dataList, currentIndex: currentIndex + 1, completion: completion)
            return
        }

        let mtu = device.peripheral?.maximumWriteValueLength(for: .withResponse) ?? defaultMtu
        sendDataInChunks(device: device, path: item.path, data: bytes, mtu: mtu) { err in
            if let err = err {
                completion(false)
            } else {
                self.sendCustomDataSequentially(device: device, dataList: dataList, currentIndex: currentIndex + 1, completion: completion)
            }
        }
    }

    private func sendDataInChunks(device: ESPDevice,
                                  path: String,
                                  data: Data,
                                  mtu: Int,
                                  completion: @escaping (Error?) -> Void) {
        var offset = 0
        let length = data.count

        func sendNext() {
            if offset >= length {
                completion(nil); return
            }
            let size = min(mtu, length - offset)
            let chunk = data.subdata(in: offset..<offset+size)

            device.sendData(path: path, data: chunk) { resp, err in
                if let err = err {
                    completion(err); return
                }

                offset += size
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    sendNext()
                }
            }
        }
        sendNext()
    }

    private func startWifiProvisioning(device: ESPDevice,
                                       ssid: String,
                                       passphrase: String) {
        device.provision(ssid: ssid, passPhrase: passphrase) { status, err in
            if let err = err {
                ESPErrorHandler.handle(error: err, result: self.result); return
            }
            switch status {
            case .success:
                self.result(true)
            case .configApplied:
                NSLog("WiFi config applied. Awaiting success.")
            case .failure:
                self.result(false)
            default:
                NSLog("Provisioning status: \(status)")
            }
        }
    }

    private func connect(deviceName: String,
                         proofOfPossession: String,
                         completion: @escaping (ESPDevice?) -> Void) {
        ESPProvisionManager.shared.createESPDevice(deviceName: deviceName,
                                                   transport: .ble,
                                                   security: .secure,
                                                   proofOfPossession: proofOfPossession) { dev, err in
            if let err = err {
                ESPErrorHandler.handle(error: err, result: self.result); completion(nil); return
            }
            guard let dev = dev else {
                self.result(FlutterError(code: "NO_DEVICE", message: "ESPDevice is nil", details: nil))
                completion(nil); return
            }

            dev.connect { stat, err in
                if let err = err {
                    ESPErrorHandler.handle(error: err, result: self.result); completion(nil); return
                }
                switch stat {
                case .connected:
                    completion(dev)
                default:
                    ESPErrorHandler.handle(error: NSError(domain: "CONNECT", code: -1, userInfo: [NSLocalizedDescriptionKey: "Status: \(stat)"]), result: self.result)
                    completion(nil)
                }
            }
        }
    }
}

private class ESPErrorHandler {
    static func handle(error: Error, result: FlutterResult) {
        if let e = error as? ESPError {
            result(FlutterError(code: "\(e.code)", message: e.description, details: e.localizedDescription))
        } else {
            result(FlutterError(code: "NATIVE_ERROR", message: error.localizedDescription, details: nil))
        }
    }
}