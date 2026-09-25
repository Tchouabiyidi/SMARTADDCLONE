import 'package:video_player/video_player.dart';

VideoPlayerController createTvVideoController(String path) =>
    throw UnsupportedError(
        'TV video playback is unavailable on this platform.');

Future<void> configureTvVideoControllerForPlayback(
    VideoPlayerController controller) async {}
