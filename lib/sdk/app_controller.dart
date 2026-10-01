import 'package:flutter/foundation.dart';

import 'client/client_session.dart';
import 'host/host_session.dart';
import 'model/device_identity.dart';
import 'model/device_metrics.dart';
import 'model/player_color.dart';
import 'model/preferred_color.dart';
import 'audio/soloud_output.dart';
import 'audio/soloud_tone_output.dart';
import 'monetization/premium_status.dart';
import 'net/loopback_transport.dart';
import 'net/websocket_transport.dart';

enum AppRole { host, join }

class AppController extends ChangeNotifier {
  AppController({PremiumStatus? premium})
    : premium = premium ?? PremiumStatus();

  final PremiumStatus premium;

  AppRole? _role;

  String? _deviceId;

  String? get seatFingerprint {
    final id = _deviceId;
    return id == null ? null : DeviceIdentity.fingerprint(id);
  }

  Future<void> warmUp() async {
    _deviceId ??= await DeviceIdentity.load();
    _preferredColor ??= await PreferredColor.load();
  }

  PlayerColor? _preferredColor;

  void _rememberColor(PlayerColor color) {
    _preferredColor = color;
    PreferredColor.save(color);
  }

  HostSession? _host;
  ClientSession? _client;
  LoopbackPair? _loopback;
  String? _error;
  bool _busy = false;

  AppRole? get role => _role;
  HostSession? get host => _host;
  ClientSession? get client => _client;
  String? get error => _error;
  bool get busy => _busy;
  bool get isHost => _role == AppRole.host;

  Future<void> startHost(DeviceMetrics metrics, {required String name}) async {
    _begin(AppRole.host);
    try {
      final host = HostSession(name: name, premium: premium);
      await host.start();
      await warmUp();

      final loopback = LoopbackPair();
      final client = ClientSession(
        transport: loopback.transport,
        metrics: metrics,
        onColorChosen: _rememberColor,
        audioOutput: SoLoudOutput(),
        toneOutput: SoLoudToneOutput(),
      );

      await client.connect();
      host.addLocalPeer(loopback.peer, preferredColor: _preferredColor);

      _host = host..addListener(notifyListeners);
      _client = client..addListener(notifyListeners);
      _loopback = loopback;
    } catch (e) {
      _error = '$e';
      _role = null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> joinHost(
    Uri uri,
    DeviceMetrics metrics, {
    required String code,
  }) async {
    _begin(AppRole.join);
    try {
      await warmUp();
      final client = ClientSession(
        transport: WebSocketTransport(uri),
        metrics: metrics,
        joinCode: code,
        deviceId: _deviceId,
        preferredColor: _preferredColor,
        onColorChosen: _rememberColor,
        audioOutput: SoLoudOutput(),
        toneOutput: SoLoudToneOutput(),
      );
      await client.connect();
      _client = client..addListener(notifyListeners);
    } catch (e) {
      _error = '$e';
      _role = null;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _begin(AppRole role) {
    _role = role;
    _error = null;
    _busy = true;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void leave() {
    _client?.removeListener(notifyListeners);
    _host?.removeListener(notifyListeners);
    _client?.dispose();
    _host?.dispose();
    _loopback?.dispose();
    _client = null;
    _host = null;
    _loopback = null;
    _role = null;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.dispose();
    _host?.dispose();
    _loopback?.dispose();
    super.dispose();
  }
}
