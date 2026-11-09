import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'platform_stub.dart' if (dart.library.io) 'platform_io.dart';

/// Hold-to-talk recording. Audio is kept in memory/temp only, uploaded once,
/// then deleted. Never saved to the gallery or app history.
class VoiceRecorder {
  final _rec = AudioRecorder();
  String? _path;

  Future<bool> start() async {
    try {
      if (!await _rec.hasPermission()) return false;
      String path = '';
      if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        path = '${dir.path}/q_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _rec.start(RecordConfig(encoder: kIsWeb ? AudioEncoder.opus : AudioEncoder.aacLc, numChannels: 1, sampleRate: 16000, bitRate: 32000),
          path: path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns (bytes, filename) or null.
  Future<(List<int>, String)?> stop() async {
    try {
      _path = await _rec.stop();
      if (_path == null) return null;
      final bytes = await readRecording(_path!);
      await _deleteTemp();
      return (bytes, kIsWeb ? 'question.webm' : 'question.m4a');
    } catch (_) {
      return null;
    }
  }

  Future<void> _deleteTemp() async {
    if (kIsWeb || _path == null) return;
    try {
      await deleteTempFile(_path!);
    } catch (_) {}
  }

  Future<void> cancel() async {
    try {
      await _rec.cancel();
    } catch (_) {}
  }

  void dispose() => _rec.dispose();
}
