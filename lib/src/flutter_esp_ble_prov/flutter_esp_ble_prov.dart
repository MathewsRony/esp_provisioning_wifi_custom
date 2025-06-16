import 'flutter_esp_ble_prov_platform_interface.dart';

/// Plugin provides core functionality to provision ESP32 devices over BLE
class FlutterEspBleProv {
  /// Initiates a scan of BLE devices with the given [prefix].
  ///
  /// ESP32 Arduino demo defaults this value to "PROV_"
  Future<List<String>> scanBleDevices(String prefix) {
    return FlutterEspBleProvPlatform.instance.scanBleDevices(prefix);
  }

  /// Scan the available WiFi networks for the given [deviceName] and
  /// [proofOfPossession] string.

  /// This library uses SECURITY_1 by default which insists on a
  /// [proofOfPossession] string. ESP32 Arduino demo defaults this value to
  /// "abcd1234"
  Future<List<String>> scanWifiNetworks(
    String deviceName,
    String proofOfPossession,
  ) {
    return FlutterEspBleProvPlatform.instance.scanWifiNetworks(
      deviceName,
      proofOfPossession,
    );
  }

  /// Provision the named WiFi network at [ssid] with the given [passphrase] for
  /// the named device [deviceName] and [proofOfPossession] string.
  Future<bool?> provisionWifi(
    String deviceName,
    String proofOfPossession,
    String ssid,
    String passphrase,
    String prov_token,
    String thing_id,
    String claim_cert,
    String claim_key,
    String ca_cert,
    String mqtt_url,
  ) {
    return FlutterEspBleProvPlatform.instance.provisionWifi(
      deviceName,
      proofOfPossession,
      ssid,
      passphrase,
      prov_token,
      thing_id,
      claim_cert,
      claim_key,
      ca_cert,
      mqtt_url,
    );
  }

  /// Returns the native platform version
  Future<String?> getPlatformVersion() {
    return FlutterEspBleProvPlatform.instance.getPlatformVersion();
  }
}
