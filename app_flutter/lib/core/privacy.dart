import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hides app content in the Android recent-apps preview and blocks screenshots
/// (FLAG_SECURE, set natively in MainActivity). No-op on web.
class ScreenPrivacy {
  static const _ch = MethodChannel('nextstep/privacy');

  static Future<void> setSecure(bool on) async {
    if (kIsWeb) return;
    try {
      await _ch.invokeMethod('setSecure', on);
    } catch (_) {}
  }
}
