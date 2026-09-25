import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config.dart';
import '../services/device_mode.dart';
import '../services/tv_cache.dart';
import '../services/tv_player.dart';
import '../theme.dart';

/// True when the app is launched with --dart-define=TV_SIMULATION=true.
const bool _tvSimulation =
    bool.fromEnvironment('TV_SIMULATION', defaultValue: false);
bool get _linuxTvSimulation =>
    _tvSimulation && !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

class SmartAdsTvApp extends StatelessWidget {
  const SmartAdsTvApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SMARTADS TV',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const TvScreen(),
      );
}

class TvScreen extends StatefulWidget {
  const TvScreen({super.key});

  @override
  State<TvScreen> createState() => _TvScreenState();
}

class _TvScreenState extends State<TvScreen> {
  final cache = TvCache();
  SharedPreferences? preferences;
  WebSocketChannel? socket;
  StreamSubscription<dynamic>? socketSubscription;
  Timer? pairingTimer;
  Timer? schedulerTimer;
  Timer? reconnectTimer;
  Timer? heartbeatTimer;
  Map<String, dynamic>? pairing;
  Map<String, dynamic>? device;
  String? deviceToken;
  List<Map<String, dynamic>> schedule = [];
  VideoPlayerController? player;
  String? activeBookingId;
  String status = 'Starting SMARTADS TV…';
  bool connected = false;
  bool startingPlayback = false;
  Duration serverOffset = Duration.zero;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Orientation lock only on real Android TV; desktop ignores or throws.
    if (!_tvSimulation && !kIsWeb) {
      SystemChrome.setPreferredOrientations(
          [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
    _initialize();
  }

  Future<void> _initialize() async {
    preferences = await SharedPreferences.getInstance();
    if (_linuxTvSimulation) await _resetLinuxSimulation();

    final storedDevice = preferences!.getString('tv.device');
    deviceToken = preferences!.getString('tv.token');
    final storedSchedule = preferences!.getString('tv.schedule');
    if (storedDevice != null && deviceToken != null) {
      device = Map<String, dynamic>.from(jsonDecode(storedDevice) as Map);
      if (storedSchedule != null) {
        schedule = (jsonDecode(storedSchedule) as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
      if (mounted) setState(() => status = 'Connecting…');
      _connectSocket();
      await _refreshSchedule();
    } else {
      await _startPairing();
    }
    schedulerTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _runSchedule());
    heartbeatTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _heartbeat());
  }

  Future<void> _resetLinuxSimulation() async {
    final storedDevice = preferences!.getString('tv.device');
    final storedToken = preferences!.getString('tv.token');
    var serverUnpaired = false;

    if (storedDevice != null && storedToken != null) {
      deviceToken = storedToken;
      try {
        final savedDevice =
            Map<String, dynamic>.from(jsonDecode(storedDevice) as Map);
        final deviceId = '${savedDevice['id'] ?? ''}';
        if (deviceId.isNotEmpty) {
          await _jsonRequest(
            'POST',
            '/api/tv/unpair?deviceId=${Uri.encodeQueryComponent(deviceId)}',
            deviceAuth: true,
          );
          serverUnpaired = true;
        }
      } catch (_) {
        // If the backend is unavailable, still start a fresh simulator identity.
      }
    }

    await preferences!.remove('tv.device');
    await preferences!.remove('tv.token');
    await preferences!.remove('tv.schedule');
    if (!serverUnpaired) await preferences!.remove('tv.installationId');
    await cache.clear();
  }

  Future<Map<String, dynamic>> _jsonRequest(String method, String path,
      {Object? body, bool deviceAuth = false}) async {
    final request = http.Request(method, Uri.parse('$apiBase$path'));
    request.headers['accept'] = 'application/json';
    if (deviceAuth) request.headers['authorization'] = 'Device $deviceToken';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await request.send());
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(decoded['error'] ?? 'TV request failed.');
    }
    return decoded;
  }

  Future<void> _startPairing() async {
    pairingTimer?.cancel();
    try {
      var installationId = preferences!.getString('tv.installationId');
      if (installationId == null) {
        installationId = base64Url.encode(
            List<int>.generate(32, (_) => Random.secure().nextInt(256)));
        await preferences!.setString('tv.installationId', installationId);
      }
      final information = await DeviceMode.tvInfo();
      Position? position;
      try {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          position = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                  accuracy: LocationAccuracy.medium,
                  timeLimit: Duration(seconds: 10)));
        }
      } catch (_) {
        // Some Android TVs do not expose a location provider.
      }
      pairing = await _jsonRequest('POST', '/api/tv/pairings', body: {
        'deviceName': information['model'] == null
            ? 'SMARTADS Android TV'
            : 'SMARTADS ${information['model']}',
        'installationId': installationId,
        'hardwareId': information['androidId'],
        'metadata': information,
        if (position != null) 'latitude': position.latitude,
        if (position != null) 'longitude': position.longitude,
        if (position != null) 'locationAccuracy': position.accuracy,
      });
      if (mounted) {
        setState(() => status = 'Scan the QR code to connect this TV');
      }
      pairingTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _pollPairing());
    } catch (error) {
      if (mounted) setState(() => status = 'Cannot reach SMARTADS: $error');
      reconnectTimer = Timer(const Duration(seconds: 8), _startPairing);
    }
  }

  Future<void> _pollPairing() async {
    final current = pairing;
    if (current == null) return;
    try {
      final result = await _jsonRequest('GET',
          '/api/tv/pairings/${current['pairingId']}/status?secret=${Uri.encodeQueryComponent('${current['secret']}')}');
      if (result['status'] == 'expired') return _startPairing();
      if (result['status'] != 'approved') return;
      pairingTimer?.cancel();
      device = Map<String, dynamic>.from(result['device'] as Map);
      deviceToken = '${result['token']}';
      await preferences!.setString('tv.device', jsonEncode(device));
      await preferences!.setString('tv.token', deviceToken!);
      if (mounted) {
        setState(() {
          pairing = null;
          status = 'Paired · loading schedule';
        });
      }
      _connectSocket();
      await _refreshSchedule();
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Waiting to pair · connection retrying');
      }
    }
  }

  Uri get _socketUri {
    final base = Uri.parse(apiBase);
    return base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/api/tv/socket',
        query: null);
  }

  void _connectSocket() {
    if (device == null || deviceToken == null) return;
    socketSubscription?.cancel();
    socket?.sink.close();
    try {
      socket = WebSocketChannel.connect(_socketUri);
      socket!.sink.add(jsonEncode({
        'type': 'device.hello',
        'deviceId': device!['id'],
        'token': deviceToken,
        'appVersion': '1.0.0',
      }));
      socketSubscription = socket!.stream.listen((data) {
        final message = Map<String, dynamic>.from(jsonDecode('$data') as Map);
        if (message['type'] == 'schedule.snapshot') _applySnapshot(message);
        if (message['type'] == 'device.heartbeat.ack') {
          _syncClock('${message['serverTime']}');
        }
        if (message['type'] == 'device.revoked') _resetPairing();
      }, onError: (_) => _socketClosed(), onDone: _socketClosed);
      if (mounted) {
        setState(() {
          connected = true;
          status = 'Connected';
        });
      }
    } catch (_) {
      _socketClosed();
    }
  }

  void _socketClosed() {
    if (mounted) {
      setState(() {
        connected = false;
        status = 'Offline · cached schedule remains active';
      });
    }
    reconnectTimer?.cancel();
    reconnectTimer = Timer(const Duration(seconds: 5), _connectSocket);
  }

  Future<void> _refreshSchedule() async {
    if (device == null || deviceToken == null) return;
    try {
      final snapshot = await _jsonRequest(
          'GET', '/api/tv/schedule?deviceId=${device!['id']}',
          deviceAuth: true);
      await _applySnapshot(snapshot);
    } catch (_) {
      if (mounted) {
        setState(() {
          connected = false;
          status = 'Offline · cached schedule remains active';
        });
      }
    }
  }

  Future<void> _applySnapshot(Map<String, dynamic> snapshot) async {
    _syncClock('${snapshot['serverTime']}');
    schedule = (snapshot['items'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    await preferences?.setString('tv.schedule', jsonEncode(schedule));
    if (mounted) {
      setState(() {
        connected = true;
        status = schedule.isEmpty
            ? 'Connected · no advertisements scheduled'
            : 'Connected · schedule synchronized';
      });
    }
    for (final item in schedule) {
      unawaited(_cacheItem(item));
    }
    await _runSchedule();
  }

  void _syncClock(String value) {
    final serverTime = DateTime.tryParse(value)?.toUtc();
    if (serverTime != null) {
      serverOffset = serverTime.difference(DateTime.now().toUtc());
    }
  }

  Future<String?> _cacheItem(Map<String, dynamic> item) async {
    try {
      final path = await cache.download(
        baseUrl: apiBase,
        mediaPath: '${item['mediaPath']}',
        deviceToken: deviceToken!,
        videoId: '${item['videoId']}',
        filename: '${item['filename']}',
        mimeType: '${item['mimeType'] ?? ''}',
        sha256: '${item['sha256']}',
      );
      await _report('media.downloaded', item['bookingId']);
      return path;
    } catch (error) {
      if (mounted) {
        setState(() => status = 'Unable to cache scheduled media: $error');
      }
      return null;
    }
  }

  Future<void> _runSchedule() async {
    if (device == null || startingPlayback) return;
    final now = DateTime.now().toUtc().add(serverOffset);
    Map<String, dynamic>? active;
    for (final item in schedule) {
      final start = DateTime.tryParse('${item['startsAt']}')?.toUtc();
      final end = DateTime.tryParse('${item['endsAt']}')?.toUtc();
      if (start != null &&
          end != null &&
          !now.isBefore(start) &&
          now.isBefore(end)) {
        active = item;
        break;
      }
    }
    if (active == null) {
      if (activeBookingId != null) await _stopPlayback('playback.finished');
      return;
    }
    if (activeBookingId == active['bookingId']) return;
    startingPlayback = true;
    VideoPlayerController? pendingPlayer;
    try {
      final path = await cache.cachedPath(
              '${active['videoId']}', '${active['sha256']}') ??
          await _cacheItem(active);
      if (path == null) {
        await _report(
          'playback.failed',
          active['bookingId'],
          details: 'The scheduled video could not be downloaded or cached.',
        );
        return;
      }
      await _stopPlayback(null);
      pendingPlayer = createTvVideoController(path);
      await pendingPlayer.initialize();
      await configureTvVideoControllerForPlayback(pendingPlayer);
      await pendingPlayer.setLooping(true);
      await pendingPlayer.play();
      player = pendingPlayer;
      pendingPlayer = null;
      activeBookingId = '${active['bookingId']}';
      await _report('playback.started', activeBookingId);
      if (mounted) setState(() => status = 'Playing scheduled advertisement');
    } catch (error) {
      await pendingPlayer?.dispose();
      await _report(
        'playback.failed',
        active['bookingId'],
        details: error.toString(),
      );
      if (mounted) setState(() => status = 'Playback failed: $error');
    } finally {
      startingPlayback = false;
    }
  }

  Future<void> _stopPlayback(String? eventType) async {
    final bookingId = activeBookingId;
    activeBookingId = null;
    final oldPlayer = player;
    player = null;
    await oldPlayer?.pause();
    await oldPlayer?.dispose();
    if (eventType != null && bookingId != null) {
      await _report(eventType, bookingId);
    }
    if (mounted) setState(() {});
  }

  Future<void> _heartbeat() async {
    if (device == null) return;
    try {
      socket?.sink
          .add(jsonEncode({'type': 'device.heartbeat', 'appVersion': '1.0.0'}));
      await _refreshSchedule();
    } catch (_) {}
  }

  Future<void> _report(String type, Object? bookingId,
      {String details = ''}) async {
    if (!connected || device == null) return;
    try {
      await _jsonRequest('POST', '/api/tv/events?deviceId=${device!['id']}',
          deviceAuth: true,
          body: {
            'type': type,
            'bookingId': bookingId,
            if (details.isNotEmpty) 'details': details,
          });
    } catch (_) {}
  }

  Future<void> _resetPairing() async {
    await _stopPlayback(null);
    socket?.sink.close();
    await preferences?.remove('tv.device');
    await preferences?.remove('tv.token');
    device = null;
    deviceToken = null;
    schedule = [];
    await _startPairing();
  }

  @override
  void dispose() {
    pairingTimer?.cancel();
    schedulerTimer?.cancel();
    reconnectTimer?.cancel();
    heartbeatTimer?.cancel();
    socketSubscription?.cancel();
    socket?.sink.close();
    player?.dispose();
    cache.dispose();
    if (!_tvSimulation && !kIsWeb) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentPlayer = player;
    Widget content;
    if (currentPlayer != null && currentPlayer.value.isInitialized) {
      content = ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: currentPlayer.value.aspectRatio,
            child: VideoPlayer(currentPlayer),
          ),
        ),
      );
    } else {
      final currentPairing = pairing;
      content = Scaffold(
        backgroundColor: const Color(0xFF071A21),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(42),
              child: currentPairing == null
                  ? _statusView()
                  : _pairingView(currentPairing),
            ),
          ),
        ),
      );
    }
    // Wrap with simulation badge when running on desktop
    if (_tvSimulation) {
      return Stack(
        children: [
          content,
          Positioned(
            top: 12,
            right: 12,
            child: _SimulationBadge(connected: connected),
          ),
        ],
      );
    }
    return content;
  }

  Widget _pairingView(Map<String, dynamic> value) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            color: Colors.white,
            child: QrImageView(data: '${value['qrData']}', size: 270),
          ),
          const SizedBox(width: 54),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SMARTADS TV',
                    style: TextStyle(
                        color: Color(0xFF75D5C2),
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2)),
                const SizedBox(height: 20),
                const Text('Connect this screen',
                    style:
                        TextStyle(fontSize: 36, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                const Text(
                    'Open SMARTADS on an administrator or owner phone and scan this QR code.',
                    style: TextStyle(
                        fontSize: 18, color: Colors.white70, height: 1.4)),
                const SizedBox(height: 28),
                Text('${value['userCode']}',
                    style: const TextStyle(
                        fontSize: 34,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                Text(status, style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ],
      );

  Widget _statusView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                  color: teal, borderRadius: BorderRadius.circular(26)),
              child: const Icon(Icons.play_arrow_rounded, size: 64)),
          const SizedBox(height: 24),
          const Text('SMARTADS',
              style: TextStyle(
                  fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: 4)),
          const SizedBox(height: 14),
          Text('${device?['billboardName'] ?? ''}',
              style: const TextStyle(fontSize: 20, color: Colors.white70)),
          const SizedBox(height: 24),
          Text(status,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16,
                  color: connected
                      ? const Color(0xFF75D5C2)
                      : Colors.orangeAccent)),
          if (schedule.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
                '${schedule.length} advertisement${schedule.length == 1 ? '' : 's'} cached or scheduled',
                style: const TextStyle(color: Colors.white54)),
          ],
        ],
      );
}

/// Overlay badge shown in the corner when running in TV simulation mode on desktop.
class _SimulationBadge extends StatefulWidget {
  const _SimulationBadge({required this.connected});
  final bool connected;

  @override
  State<_SimulationBadge> createState() => _SimulationBadgeState();
}

class _SimulationBadgeState extends State<_SimulationBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor =
        widget.connected ? const Color(0xFF4ADE80) : Colors.orangeAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing dot
          FadeTransition(
            opacity: _pulse,
            child: Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 7),
          const Icon(Icons.computer_rounded, size: 13, color: Colors.white70),
          const SizedBox(width: 5),
          const Text(
            'SIMULATION MODE',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
