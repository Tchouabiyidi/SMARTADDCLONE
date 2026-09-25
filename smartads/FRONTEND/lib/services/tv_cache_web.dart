// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

class TvCache {
  final Map<String, String> _objectUrls = {};
  final Map<String, Future<String>> _downloads = {};

  String _key(String videoId, String sha256) => '$videoId:$sha256';

  Future<String?> cachedPath(String videoId, String expectedSha) async =>
      _objectUrls[_key(videoId, expectedSha)];

  Future<String> download({
    required String baseUrl,
    required String mediaPath,
    required String deviceToken,
    required String videoId,
    required String filename,
    required String mimeType,
    required String sha256,
  }) async {
    final key = _key(videoId, sha256);
    final cached = _objectUrls[key];
    if (cached != null) return cached;

    final pending = _downloads[key];
    if (pending != null) return pending;

    final future = _download(
      key: key,
      baseUrl: baseUrl,
      mediaPath: mediaPath,
      deviceToken: deviceToken,
      filename: filename,
      mimeType: mimeType,
      sha256: sha256,
    );
    _downloads[key] = future;
    try {
      return await future;
    } finally {
      _downloads.remove(key);
    }
  }

  Future<String> _download({
    required String key,
    required String baseUrl,
    required String mediaPath,
    required String deviceToken,
    required String filename,
    required String mimeType,
    required String sha256,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl$mediaPath'),
      headers: {'Authorization': 'Device $deviceToken'},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Media download failed (${response.statusCode}).');
    }

    final digest = crypto.sha256.convert(response.bodyBytes).toString();
    if (digest != sha256) {
      throw const FormatException('Downloaded video checksum does not match.');
    }

    final resolvedMimeType = mimeType.startsWith('video/')
        ? mimeType
        : filename.toLowerCase().endsWith('.webm')
            ? 'video/webm'
            : filename.toLowerCase().endsWith('.mov')
                ? 'video/quicktime'
                : 'video/mp4';
    final blob = html.Blob([response.bodyBytes], resolvedMimeType);
    final objectUrl = html.Url.createObjectUrlFromBlob(blob);
    _objectUrls[key] = objectUrl;
    return objectUrl;
  }

  Future<void> clear() async {
    for (final objectUrl in _objectUrls.values.toSet()) {
      html.Url.revokeObjectUrl(objectUrl);
    }
    _objectUrls.clear();
    _downloads.clear();
  }

  void dispose() {
    for (final objectUrl in _objectUrls.values.toSet()) {
      html.Url.revokeObjectUrl(objectUrl);
    }
    _objectUrls.clear();
    _downloads.clear();
  }
}
