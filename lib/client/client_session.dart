import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/coverage_map.dart';
import '../model/device_metrics.dart';
import '../model/phone_layout.dart';
import '../model/world_rect.dart';
import '../net/protocol.dart';
import '../net/transport.dart';
import 'snapshot_buffer.dart';

enum ClientPhase { connecting, lobby, placing, playing, rejected, disconnected }

/// One phone's view of the game: a viewport, nothing more.
///
/// It sends raw local touches up and renders whatever the host describes. It
/// runs no physics — which is exactly why every screen agrees on the world.
class ClientSession extends ChangeNotifier {
  ClientSession({
    required Transport transport,
    required DeviceMetrics metrics,
    String? joinCode,
  }) : _transport = transport,
       _metrics = metrics,
       _joinCode = joinCode;

  final Transport _transport;
  DeviceMetrics _metrics;

  /// The 5-digit code proving we were invited. Null on the host's own
  /// loopback, which the host trusts without asking.
  final String? _joinCode;

  final buffer = SnapshotBuffer();
  final _clock = Stopwatch()..start();

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _pingTimer;

  ClientPhase _phase = ClientPhase.connecting;
  String? _phoneId;
  PhoneLayout? _layout;
  CoverageMap? _coverage;
  WorldRect? _board;
  List<EntitySpec> _specs = const [];
  List<Map<String, dynamic>> _lobbyPhones = const [];
  String? _message;
  double? _rttMs;
  double? _anchorX;
  double? _anchorY;

  ClientPhase get phase => _phase;
  String? get phoneId => _phoneId;

  /// What the host calls this game, once we are in.
  String? get gameName => _gameName;
  String? _gameName;
  PhoneLayout? get layout => _layout;
  CoverageMap? get coverage => _coverage;
  WorldRect? get board => _board;
  List<EntitySpec> get specs => _specs;
  List<Map<String, dynamic>> get lobbyPhones => _lobbyPhones;
  String? get message => _message;
  double? get rttMs => _rttMs;
  DeviceMetrics get metrics => _metrics;

  /// Where the sling sits in world coordinates. Part of the world description,
  /// so a client knows where to aim without being told each tick.
  double? get anchorX => _anchorX;
  double? get anchorY => _anchorY;

  Future<void> connect() async {
    try {
      await _transport.connect();
      _sub = _transport.onMessage.listen(
        _handle,
        onDone: () => _fail(ClientPhase.disconnected, 'Connection closed.'),
        onError: (Object e) => _fail(ClientPhase.disconnected, '$e'),
      );
      // The code first, before anything else: the host ignores every other
      // message until it has one, and answers `welcome` only once it matches.
      _transport.send({
        'type': ClientMsg.join,
        if (_joinCode != null) 'code': _joinCode,
      });
      _sendCalibration();
      _pingTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _sendPing());
    } catch (e) {
      _fail(ClientPhase.disconnected, _friendlyError(e));
    }
  }

  static String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('TimeoutException') || s.contains('timed out')) {
      return 'No answer from the host. Same WiFi? Some public networks block '
          'devices from seeing each other.';
    }
    if (s.contains('refused')) {
      return 'Host refused the connection. Is the host screen still open?';
    }
    return s;
  }

  void _fail(ClientPhase phase, String message) {
    _phase = phase;
    _message = message;
    notifyListeners();
  }

  /// Re-report our physical size (the user corrected a measurement).
  void updateMetrics(DeviceMetrics metrics) {
    _metrics = metrics;
    _sendCalibration();
    notifyListeners();
  }

  void _sendCalibration() {
    _transport.send({
      'type': ClientMsg.calibration,
      'phoneId': _phoneId,
      'metrics': _metrics.toJson(),
    });
  }

  void _sendPing() {
    _transport.send({
      'type': ClientMsg.ping,
      't': _clock.elapsedMilliseconds,
      if (_rttMs != null) 'rtt': _rttMs,
    });
  }

  void confirmPlacement() {
    _transport
        .send({'type': ClientMsg.confirmPlacement, 'phoneId': _phoneId});
  }

  void sendReset() => _transport.send({'type': ClientMsg.reset});

  /// Forward a touch as raw local pixels.
  ///
  /// Flutter gestures arrive in logical pixels; we scale to *physical* pixels so
  /// the wire format carries no notion of this device's scale factor. The host
  /// converts to world coordinates, since only it knows where this screen sits.
  void sendTouch(double logicalX, double logicalY, String phase) {
    final dpr = _metrics.devicePixelRatio;
    _transport.send({
      'type': ClientMsg.touch,
      'phoneId': _phoneId,
      'lx': logicalX * dpr,
      'ly': logicalY * dpr,
      'phase': phase,
    });
  }

  void _handle(Map<String, dynamic> msg) {
    switch (msg['type'] as String?) {
      case HostMsg.welcome:
        if (msg['rejected'] == true) {
          _fail(ClientPhase.rejected, msg['reason'] as String? ?? 'Rejected.');
          return;
        }
        _phoneId = msg['phoneId'] as String;
        _gameName = msg['gameName'] as String?;
        _phase = ClientPhase.lobby;
        // Re-send now that we have an id attached.
        _sendCalibration();
        notifyListeners();

      case HostMsg.lobby:
        _lobbyPhones = [
          for (final p in msg['phones'] as List) p as Map<String, dynamic>,
        ];
        notifyListeners();

      case HostMsg.layout:
        _layout = PhoneLayout.fromJson(msg);
        _coverage =
            CoverageMap.fromJson(msg['coverage'] as Map<String, dynamic>);
        _board = _layout!.board;
        _phase = ClientPhase.placing;
        buffer.clear();
        notifyListeners();

      case HostMsg.worldInit:
        _board = WorldRect.fromJson(msg['board'] as Map<String, dynamic>);
        final anchor = msg['anchor'] as Map<String, dynamic>?;
        _anchorX = (anchor?['x'] as num?)?.toDouble();
        _anchorY = (anchor?['y'] as num?)?.toDouble();
        _specs = [
          for (final e in msg['entities'] as List)
            EntitySpec.fromJson(e as Map<String, dynamic>),
        ];
        notifyListeners();

      case HostMsg.start:
        _phase = ClientPhase.playing;
        buffer.clear();
        notifyListeners();

      case HostMsg.state:
        buffer.add(Snapshot(
          tick: (msg['tick'] as num).toInt(),
          hostTimeMs: (msg['t'] as num).toDouble(),
          entities: {
            for (final e in msg['entities'] as List)
              (e as Map<String, dynamic>)['id'] as String:
                  EntityState.fromJson(e),
          },
          sling: msg['sling'] == null
              ? null
              : SlingState.fromJson(msg['sling'] as Map<String, dynamic>),
        ));
        // No notifyListeners: 60Hz state drives the Flame render loop directly,
        // not the widget tree.

      case HostMsg.pong:
        final sent = (msg['t'] as num).toDouble();
        _rttMs = _clock.elapsedMilliseconds - sent;
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _sub?.cancel();
    _transport.dispose();
    super.dispose();
  }
}
