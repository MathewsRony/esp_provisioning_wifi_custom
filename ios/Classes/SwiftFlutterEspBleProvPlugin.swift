import Flutter
import UIKit
import ESPProvision

public class SwiftFlutterEspBleProvPlugin: NSObject, FlutterPlugin {
    private let SCAN_BLE_DEVICES = "scanBleDevices"
    private let SCAN_WIFI_NETWORKS = "scanWifiNetworks"
    private let PROVISION_WIFI = "provisionWifi"

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "flutter_esp_ble_prov", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterEspBleProvPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let provisionService = BLEProvisionService(result: result)
        let arguments = call.arguments as! [String: Any]

        switch call.method {
        case SCAN_BLE_DEVICES:
            let prefix = arguments["prefix"] as! String
            provisionService.searchDevices(prefix: prefix)
        case SCAN_WIFI_NETWORKS:
            let deviceName = arguments["deviceName"] as! String
            let pop = arguments["proofOfPossession"] as! String
            provisionService.scanWifiNetworks(deviceName: deviceName, proofOfPossession: pop)
        case PROVISION_WIFI:
            let deviceName = arguments["deviceName"] as! String
            let pop = arguments["proofOfPossession"] as! String
            let ssid = arguments["ssid"] as! String
            let pass = arguments["passphrase"] as! String
            let customData = arguments["prov_token"] as! String
            provisionService.provision(deviceName: deviceName, proofOfPossession: pop, ssid: ssid, passphrase: pass, customData: customData)
        default:
            result("iOS " + UIDevice.current.systemVersion)
        }
    }
}

protocol ProvisionService {
    var result: FlutterResult { get }
    func searchDevices(prefix: String)
    func scanWifiNetworks(deviceName: String, proofOfPossession: String)
    func provision(deviceName: String, proofOfPossession: String, ssid: String, passphrase: String, customData: String)
}

private class BLEProvisionService: ProvisionService {
    fileprivate var result: FlutterResult

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
        self.connect(deviceName: deviceName, proofOfPossession: proofOfPossession) { device in
            device?.scanWifiList { wifiList, error in
                if let error = error {
                    NSLog("Error scanning wifi networks, deviceName: \(deviceName)")
                    ESPErrorHandler.handle(error: error, result: self.result)
                } else {
                    self.result(wifiList?.map { $0.ssid })
                    device?.disconnect()
                }
            }
        }
    }

    func provision(deviceName: String, proofOfPossession: String, ssid: String, passphrase: String, customData: String = "") {
        self.connect(deviceName: deviceName, proofOfPossession: proofOfPossession) { device in
            guard let device = device else {
                self.result(FlutterError(code: "DEVICE_NULL", message: "Device connection failed", details: nil))
                return
            }

            if customData.isEmpty {
                self.startWifiProvisioning(device: device, ssid: ssid, passphrase: passphrase)
                return
            }

            NSLog("Sending custom data before provisioning: \(customData)")
            // Convert string to Data
            device.sendData(path: "custom-data", data: Data(customData.utf8)) { response, error in
                if let error = error {
                    NSLog("Error receiving custom data response: \(error.localizedDescription)")
                } else if let response = response {
                    let responseStr = String(data: response, encoding: .utf8) ?? "null"
                    NSLog("Custom data response: \(responseStr)")
                }
                self.startWifiProvisioning(device: device, ssid: ssid, passphrase: passphrase)
            }
        }
    }

    private func startWifiProvisioning(device: ESPDevice, ssid: String, passphrase: String) {
        device.provision(ssid: ssid, passPhrase: passphrase) { status in
            switch status {
            case .success:
                NSLog("deviceProvisioningSuccess")
                self.result(true)
            case .configApplied:
                NSLog("wifiConfigApplied")
            case .failure:
                NSLog("wifiConfigFailed")
                self.result(false)
            }
        }
    }

    private func connect(deviceName: String, proofOfPossession: String, completionHandler: @escaping (ESPDevice?) -> Void) {
        ESPProvisionManager.shared.createESPDevice(deviceName: deviceName, transport: .ble, security: .secure, proofOfPossession: proofOfPossession) { espDevice, error in
            if let error = error {
                ESPErrorHandler.handle(error: error, result: self.result)
                return
            }

            espDevice?.connect { status in
                switch status {
                case .connected:
                    completionHandler(espDevice!)
                case let .failedToConnect(error):
                    ESPErrorHandler.handle(error: error, result: self.result)
                default:
                    self.result(FlutterError(code: "DEVICE_DISCONNECTED", message: nil, details: nil))
                }
            }
        }
    }
}

private class ESPErrorHandler {
    static func handle(error: ESPError, result: FlutterResult) {
        result(FlutterError(code: String(error.code), message: error.description, details: nil))
    }
}
