class TvCache {
  Future<String?> cachedPath(String videoId, String sha256) async => null;
  Future<String> download({
    required String baseUrl,
    required String mediaPath,
    required String deviceToken,
    required String videoId,
    required String filename,
    required String mimeType,
    required String sha256,
  }) =>
      throw UnsupportedError(
          'TV media caching is unavailable on this platform.');

  Future<void> clear() async {}

  void dispose() {}
}
