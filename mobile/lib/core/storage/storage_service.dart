import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/paired_host.dart';

class StorageService {
  static const _keyMobileDeviceId = 'ag_mobile_device_id';
  static const _keyPrivateKeyRaw = 'ag_mobile_private_key_raw';
  static const _keyPairedHosts = 'ag_paired_hosts_list';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Get or create persistent device ID
  Future<String> getOrCreateDeviceId() async {
    String? deviceId = await _secureStorage.read(key: _keyMobileDeviceId);
    if (deviceId == null) {
      deviceId = 'mobile-${const Uuid().v4()}';
      await _secureStorage.write(key: _keyMobileDeviceId, value: deviceId);
    }
    return deviceId;
  }

  /// Store or read Base64 raw private key in Android Keystore
  Future<String?> getPrivateKeyBase64() async {
    return await _secureStorage.read(key: _keyPrivateKeyRaw);
  }

  Future<void> savePrivateKeyBase64(String rawKey) async {
    await _secureStorage.write(key: _keyPrivateKeyRaw, value: rawKey);
  }

  /// Paired Hosts list persistence
  Future<List<PairedHost>> getPairedHosts() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_keyPairedHosts);
    if (jsonString == null) return [];

    try {
      final List decoded = jsonDecode(jsonString) as List;
      return decoded.map((e) => PairedHost.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePairedHost(PairedHost host) async {
    final hosts = await getPairedHosts();
    final index = hosts.indexWhere((h) => h.hostDeviceId == host.hostDeviceId);
    if (index >= 0) {
      hosts[index] = host;
    } else {
      hosts.add(host);
    }
    await _saveHostsList(hosts);
  }

  Future<void> removePairedHost(String hostDeviceId) async {
    final hosts = await getPairedHosts();
    hosts.removeWhere((h) => h.hostDeviceId == hostDeviceId);
    await _saveHostsList(hosts);
  }

  Future<void> _saveHostsList(List<PairedHost> hosts) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(hosts.map((h) => h.toJson()).toList());
    await prefs.setString(_keyPairedHosts, jsonString);
  }
}
