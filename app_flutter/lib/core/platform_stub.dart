import 'package:http/http.dart' as http;

Future<void> deleteTempFile(String path) async {}

/// Web: the recorder returns a blob: URL.
Future<List<int>> readRecording(String path) async => (await http.get(Uri.parse(path))).bodyBytes;
