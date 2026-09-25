import 'package:video_player/video_player.dart';

VideoPlayerController createTvVideoController(String objectUrl) =>
    VideoPlayerController.networkUrl(Uri.parse(objectUrl));

Future<void> configureTvVideoControllerForPlayback(
        VideoPlayerController controller) =>
    controller.setVolume(0);
