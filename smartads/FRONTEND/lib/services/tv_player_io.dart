import 'dart:io';

import 'package:video_player/video_player.dart';

VideoPlayerController createTvVideoController(String path) =>
    VideoPlayerController.file(File(path));

Future<void> configureTvVideoControllerForPlayback(
    VideoPlayerController controller) async {}
