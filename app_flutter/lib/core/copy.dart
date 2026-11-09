import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// All wording comes from the design copy file (copy.json) plus copy_extra.json.
/// Bundled for first launch; refreshed from the server (verified contacts filled in).
class Copy {
  Map<String, dynamic> data = {};

  Future<void> load() async {
    final a = jsonDecode(await rootBundle.loadString('assets/content/copy.json')) as Map<String, dynamic>;
    final b = jsonDecode(await rootBundle.loadString('assets/content/copy_extra.json')) as Map<String, dynamic>;
    b.forEach((k, v) {
      if (!k.startsWith('_')) a[k] = v;
    });
    data = a;
  }

  void overlay(Map<String, dynamic> fromServer) => fromServer.forEach((k, v) => data[k] = v);

  String t(List ref, String lang, [Map? params]) {
    final f = data[ref[0]];
    if (f is! Map) return '';
    var s = ((f[lang] as Map?)?[ref[1]] ?? (f['en'] as Map?)?[ref[1]] ?? '') as String;
    params?.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}
