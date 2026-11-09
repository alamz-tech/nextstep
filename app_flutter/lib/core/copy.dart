import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// All user-facing text comes from the design copy file (copy.json) plus the
/// engineering additions (copy_extra.json). Shipped as assets so the app works
/// offline; refreshed from the server's content bundle (with verified contacts filled in).
class Copy {
  Map<String, dynamic> _data = {};

  Future<void> loadAssets() async {
    final a = jsonDecode(await rootBundle.loadString('assets/content/copy.json')) as Map<String, dynamic>;
    final b = jsonDecode(await rootBundle.loadString('assets/content/copy_extra.json')) as Map<String, dynamic>;
    b.forEach((k, v) {
      if (!k.startsWith('_')) a[k] = v;
    });
    _data = a;
  }

  void overlay(Map<String, dynamic>? fromBundle) {
    if (fromBundle == null) return;
    fromBundle.forEach((k, v) => _data[k] = v);
  }

  String t(String flow, String key, String lang, [Map<String, String>? params]) {
    final f = _data[flow];
    if (f is! Map) return '';
    String s = ((f[lang] as Map?)?[key] ?? (f['en'] as Map?)?[key] ?? '') as String;
    params?.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  bool isDraft(String flow, String key) {
    final f = _data[flow];
    return f is Map && (f['_draft'] as List?)?.contains(key) == true;
  }
}
