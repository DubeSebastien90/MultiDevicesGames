import 'package:flutter/foundation.dart';

import 'client/client_session.dart';
import 'host/host_session.dart';
import 'model/device_identity.dart';
import 'model/device_metrics.dart';
import 'net/loopback_transport.dart';
import 'net/websocket_transport.dart';

enum AppRole { host, join }

/// Owns whichever sessions this device is running.
///
/// A host device runs *both* a [HostSession] and a [ClientSession]: the host is
/// a player too, and it reaches its own world through the same client code path
/// as everyone else.
class AppController extends ChangeNotifier {
  AppRole? _role;

  /// What this device calls itself, loaded once and kept for the app's life.
  ///
  /// Read from storage rather than remembered in a field the way the
  /// host-assigned number used to be: that only survived leaving and rejoining,
  /// and the case worth surviving is the app being closed — a phone that runs
  /// out of battery mid-game should come back to its own seat.
  String? _deviceId;

  /// How this device appears in a host's list of empty seats. Null until
  /// [warmUp] has finished.
  String? get seatFingerprint {
    final id = _deviceId;
    return id == null ? null : DeviceIdentity.fingerprint(id);
  }

  /// Load it now, so joining does not have to wait on storage.
  Future<void> warmUp() async {
    _deviceId ??= await DeviceIdentity.load();
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

  /// Opens a session under [name], generating the 5-digit code friends need.
  Future<void> startHost(DeviceMetrics metrics, {required String name}) async {
    _begin(AppRole.host);
    try {
      final host = HostSession(name: name);
      await host.start();

      final loopback = LoopbackPair();
      final client =
          ClientSession(transport: loopback.transport, metrics: metrics);

      // Connect (and therefore subscribe) before handing the peer to the host,
      // so the `welcome` it sends immediately has somewhere to land.
      await client.connect();
      host.addLocalPeer(loopback.peer);

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
        // Who this device is, so a session it drops out of and comes back to
        // gives it its own row in the standings rather than a second one.
        deviceId: _deviceId,
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

  /// Tear everything down and go back to role selection.
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
