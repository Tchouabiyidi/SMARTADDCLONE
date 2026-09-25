import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class TvCache {
  Future<Directory> _directory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/smartads-media');
    await directory.create(recursive: true);
    return directory;
  }

  Future<String?> cachedPath(String videoId, String expectedSha) async {
    final directory = await _directory();
    final matches = directory.listSync().whereType<File>().where((file) =>
        file.path.split(Platform.pathSeparator).last.startsWith('$videoId.'));
    for (final file in matches) {
      final digest = crypto.sha256.convert(await file.readAsBytes()).toString();
      if (digest == expectedSha) return file.path;
      await file.delete();
    }
    return null;
  }

  Future<String> download({
    required String baseUrl,
    required String mediaPath,
    required String deviceToken,
    required String videoId,
    required String filename,
    required String mimeType,
    required String sha256,
  }) async {
    final existing = await cachedPath(videoId, sha256);
    if (existing != null) return existing;
    final response = await http.get(Uri.parse('$baseUrl$mediaPath'),
        headers: {'Authorization': 'Device $deviceToken'});
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Media download failed (${response.statusCode}).');
    }
    final digest = crypto.sha256.convert(response.bodyBytes).toString();
    if (digest != sha256) {
      throw const FormatException('Downloaded video checksum does not match.');
    }
    final safeExtension = mimeType.toLowerCase().contains('webm') ||
            filename.toLowerCase().endsWith('.webm')
        ? 'webm'
        : 'mp4';
    final file = File('${(await _directory()).path}/$videoId.$safeExtension');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    return file.path;
  }

  Future<void> clear() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory('${root.path}/smartads-media');
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  void dispose() {}
}
