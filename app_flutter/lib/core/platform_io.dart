import 'dart:io';

Future<void> deleteTempFile(String path) async {
  final f = File(path);
  if (await f.exists()) await f.delete();
}
