import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypted local storage (Android Keystore-backed EncryptedSharedPreferences;
/// WebCrypto-encrypted localStorage on web). Everything NextStep keeps on the
/// device goes through here, so "delete my data" is a single call.
class Store {
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions(), // AES-GCM, key in Android Keystore
    webOptions: WebOptions(dbName: 'ns', publicKey: 'ns'),
  );

  Future<String?> read(String k) async {
    try {
      return await _s.read(key: k);
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String k, String? v) async {
    try {
      if (v == null) {
        await _s.delete(key: k);
      } else {
        await _s.write(key: k, value: v);
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> readJson(String k) async {
    final v = await read(k);
    if (v == null) return null;
    try {
      return jsonDecode(v) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeJson(String k, Object? v) => write(k, v == null ? null : jsonEncode(v));

  Future<void> wipe() async {
    try {
      await _s.deleteAll();
    } catch (_) {}
  }
}
