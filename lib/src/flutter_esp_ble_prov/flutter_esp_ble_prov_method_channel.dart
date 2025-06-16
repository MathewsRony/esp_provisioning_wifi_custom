import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_esp_ble_prov_platform_interface.dart';

/// An implementation of [FlutterEspBleProvPlatform] that uses method channels.
class MethodChannelFlutterEspBleProv extends FlutterEspBleProvPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_esp_ble_prov');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<List<String>> scanBleDevices(String prefix) async {
    final args = {'prefix': prefix};
    final raw = await methodChannel.invokeMethod<List<Object?>>(
      'scanBleDevices',
      args,
    );
    final List<String> devices = [];
    if (raw != null) {
      devices.addAll(raw.cast<String>());
    }
    return devices;
  }

  @override
  Future<List<String>> scanWifiNetworks(
    String deviceName,
    String proofOfPossession,
  ) async {
    final args = {
      'deviceName': deviceName,
      'proofOfPossession': proofOfPossession,
    };
    final raw = await methodChannel.invokeMethod<List<Object?>>(
      'scanWifiNetworks',
      args,
    );
    final List<String> networks = [];
    if (raw != null) {
      networks.addAll(raw.cast<String>());
    }
    return networks;
  }

  @override
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
  ) async {
    final args = {
      'deviceName': deviceName,
      'proofOfPossession': proofOfPossession,
      'ssid': ssid,
      'passphrase': passphrase,
      'prov_token': prov_token,
      'thing_id': thing_id,
      'claim_cert': claim_cert,
      'claim_key': claim_key,
      'ca_cert': ca_cert,
      'mqtt_url': mqtt_url,
    };
    return await methodChannel.invokeMethod<bool?>('provisionWifi', args);
  }
}
