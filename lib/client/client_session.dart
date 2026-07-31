import 'dart:async';

import 'package:flutter/foundation.dart';

import '../game/mini_game.dart';
import '../model/arrangement.dart';
import '../model/coverage_map.dart';
import '../model/device_metrics.dart';
import '../model/phone_layout.dart';
import '../model/world_rect.dart';
import '../net/protocol.dart';
import '../net/transport.dart';
import 'snapshot_buffer.dart';

enum ClientPhase {
  connecting,
  lobby,
  placing,
  playing,
  won,
  rejected,
  disconnected,
}

/// A round that was won, and what the playlist serves up next.
class WinResult {
  const WinResult({
    required this.title,
    required this.nextTitle,
    required this.nextTagline,
    required this.nextArrangement,
    this.progress,
  });

  final String title;
  final String nextTitle;
  final String nextTagline;
  final Arrangement nextArrangement;

  /// Final score, for games that kept one.
  final GameProgress? progress;

  static WinResult fromJson(Map<String, dynamic> j) {
    final p = j['progress'];
    return WinResult(
      title: (j['gameTitle'] as String?) ?? 'That round',
      nextTitle: (j['nextTitle'] as String?) ?? 'Next game',
      nextTagline: (j['nextTagline'] as String?) ?? '',
      nextArrangement:
          ArrangementInfo.fromWire(j['nextArrangement'] as String?),
      progress: p is Map<String, dynamic> ? GameProgress.fromJson(p) : null,
    );
  }
}

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

  /// The minigame currently being set up or played, as the host describes it.
  /// All display-only — a client never builds a world from this.
  String? get miniGameId => _miniGameId;
  String? get miniGameTitle => _miniGameTitle;
  String? get miniGameTagline => _miniGameTagline;
  String? get miniGameGoal => _miniGameGoal;
  String? _miniGameId;
  String? _miniGameTitle;
  String? _miniGameTagline;
  String? _miniGameGoal;

  /// How the phones should be laid out for it.
  Arrangement get arrangement => _arrangement;
  Arrangement _arrangement = Arrangement.strip;

  /// The host's phase, verbatim. The client mostly routes on its own phase; it
  /// needs this only to tell "host is picking the next game" from "host is
  /// still in the lobby".
  String? get hostPhase => _hostPhase;
  String? _hostPhase;

  /// Live score during play, for games that keep one.
  GameProgress? get progress => _progress;
  GameProgress? _progress;

  /// Set when a round is won: what was beaten, and what is next.
  WinResult? get win => _win;
  WinResult? _win;
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
        _hostPhase = msg['phase'] as String?;
        _readGameFields(msg);
        // The host went back to setting up (next round, or a re-calibrate):
        // follow it out of the win screen rather than stranding this phone on
        // a stale "you win".
        if (_phase == ClientPhase.won && _hostPhase != 'won') {
          _phase = ClientPhase.lobby;
          _win = null;
        }
        notifyListeners();

      case HostMsg.layout:
        _layout = PhoneLayout.fromJson(msg);
        _coverage =
            CoverageMap.fromJson(msg['coverage'] as Map<String, dynamic>);
        _board = _layout!.board;
        _readGameFields(msg);
        _phase = ClientPhase.placing;
        _win = null;
        _progress = null;
        buffer.clear();
        notifyListeners();

      case HostMsg.worldInit:
        _board = WorldRect.fromJson(msg['board'] as Map<String, dynamic>);
        final anchor = msg['anchor'] as Map<String, dynamic>?;
        _anchorX = (anchor?['x'] as num?)?.toDouble();
        _anchorY = (anchor?['y'] as num?)?.toDouble();
        _readGameFields(msg);
        _specs = [
          for (final e in msg['entities'] as List)
            EntitySpec.fromJson(e as Map<String, dynamic>),
        ];
        notifyListeners();

      case HostMsg.start:
        _phase = ClientPhase.playing;
        buffer.clear();
        notifyListeners();

      case HostMsg.won:
        _win = WinResult.fromJson(msg);
        _phase = ClientPhase.won;
        notifyListeners();

      case HostMsg.state:
        final p = msg['progress'];
        if (p is Map<String, dynamic>) _progress = GameProgress.fromJson(p);
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

  /// Picks up whichever game-description fields a message happens to carry.
  /// The host repeats them liberally, so this is called from several handlers.
  void _readGameFields(Map<String, dynamic> msg) {
    _miniGameId = (msg['game'] as String?) ?? _miniGameId;
    _miniGameTitle = (msg['gameTitle'] as String?) ?? _miniGameTitle;
    _miniGameTagline = (msg['gameTagline'] as String?) ?? _miniGameTagline;
    _miniGameGoal = (msg['gameGoal'] as String?) ?? _miniGameGoal;
    final arrangement = msg['arrangement'] as String?;
    if (arrangement != null) {
      _arrangement = ArrangementInfo.fromWire(arrangement);
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
