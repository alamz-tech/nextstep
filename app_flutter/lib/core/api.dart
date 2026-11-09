import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OfflineException implements Exception {}

class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// REST client for the NextStep /v1 API.
/// Web: same origin as the page. Android: --dart-define=API_BASE=https://your-server
class Api {
  Api(this.installId);

  final String installId;
  String? staffToken;

  static String get base {
    const fromEnv = String.fromEnvironment('API_BASE');
    if (fromEnv.isNotEmpty) return fromEnv;
    if (kIsWeb) return Uri.base.origin;
    return 'http://10.0.2.2:8077'; // Android emulator -> host machine
  }

  Map<String, String> _headers({bool json = true, bool staff = false}) => {
        if (json) 'Content-Type': 'application/json',
        'X-Install-ID': installId,
        if (staff && staffToken != null) 'Authorization': 'Bearer $staffToken',
      };

  Uri _u(String path, [Map<String, String>? q]) => Uri.parse('$base$path').replace(queryParameters: q);

  Future<dynamic> _send(Future<http.Response> Function() f) async {
    http.Response r;
    try {
      r = await f().timeout(const Duration(seconds: 25));
    } catch (_) {
      throw OfflineException();
    }
    if (r.statusCode == 304) return null;
    if (r.statusCode >= 400) {
      String msg = 'Error ${r.statusCode}';
      try {
        final d = jsonDecode(utf8.decode(r.bodyBytes));
        if (d is Map && d['detail'] is String) msg = d['detail'];
      } catch (_) {}
      throw ApiException(r.statusCode, msg);
    }
    final ct = r.headers['content-type'] ?? '';
    if (ct.contains('application/json')) return jsonDecode(utf8.decode(r.bodyBytes));
    return r.bodyBytes;
  }

  Future<dynamic> get(String path, {Map<String, String>? q, bool staff = false, Map<String, String>? extra}) =>
      _send(() => http.get(_u(path, q), headers: {..._headers(staff: staff), ...?extra}));

  Future<dynamic> post(String path, [Object? body, bool staff = false]) =>
      _send(() => http.post(_u(path), headers: _headers(staff: staff), body: jsonEncode(body ?? {})));

  Future<dynamic> delete(String path) => _send(() => http.delete(_u(path), headers: _headers()));

  Future<dynamic> postAudio(String path, List<int> bytes, String filename, Map<String, String> fields) async {
    final req = http.MultipartRequest('POST', _u(path))
      ..headers.addAll(_headers(json: false))
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes('audio', bytes, filename: filename));
    return _send(() async => http.Response.fromStream(await req.send()));
  }

  String absolute(String path) => path.startsWith('http') ? path : '$base$path';
}
