import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/coverage_map.dart';
import '../model/device_metrics.dart';
import '../model/phone_layout.dart';
import '../model/world_rect.dart';
import '../net/protocol.dart';
import '../net/transport.dart';
import '../catalog.dart';
import '../contract/entity.dart';
import '../contract/game.dart';
import '../contract/sim.dart' show PhoneSlice;
import '../contract/view.dart';
import '../score/scoreboard.dart';
import 'snapshot_buffer.dart';

enum ClientPhase {
  connecting,
  lobby,
  placing,
  playing,
  finished,
  rejected,
  disconnected,
}

/// A round that ended, and what the playlist serves up next.
class RoundResult {
  const RoundResult({
    required this.won,
    required this.title,
    required this.summary,
    required this.nextTitle,
    required this.nextTagline,
    required this.nextInstruction,
  });

  final bool won;
  final String title;
  final String? summary;
  final String nextTitle;
  final String nextTagline;

  /// How to rearrange the phones for what is coming.
  final String nextInstruction;

  static RoundResult fromJson(Map<String, dynamic> j) => RoundResult(
    won: j['won'] as bool? ?? true,
    title: (j['gameTitle'] as String?) ?? 'That round',
    summary: j['summary'] as String?,
    nextTitle: (j['nextTitle'] as String?) ?? 'Next game',
    nextTagline: (j['nextTagline'] as String?) ?? '',
    nextInstruction: (j['nextInstruction'] as String?) ?? '',
  );
}

/// One phone's view of the session: a viewport onto a world it does not own.
///
/// It sends raw local touches up and renders whatever the host describes. It
/// runs no simulation — which is exactly why every screen agrees.
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
  List<Map<String, dynamic>> _lobbyPhones = const [];
  String? _message;
  double? _rttMs;

  /// Descriptors for everything that can currently be drawn, by id. Built from
  /// `worldInit` and kept current by `spawn`/`despawn`.
  final _descriptors = <String, EntityDescriptor>{};

  Map<String, Object?> _sharedState = const {};
  ScoreView _scores = ScoreView.empty;
  RoundResult? _result;

  /// The game being set up or played, resolved from the catalog by id.
  MultiscreenGame? _game;
  GameView? _view;
  bool _viewLoading = false;

  String? _hostPhase;
  String? _sessionName;

  ClientPhase get phase => _phase;
  String? get phoneId => _phoneId;
  PhoneLayout? get layout => _layout;
  CoverageMap? get coverage => _coverage;
  WorldRect? get board => _board;
  List<Map<String, dynamic>> get lobbyPhones => _lobbyPhones;
  String? get message => _message;
  double? get rttMs => _rttMs;
  DeviceMetrics get metrics => _metrics;

  /// What the host called the whole session — the name in the join list.
  String? get sessionName => _sessionName;

  MultiscreenGame? get game => _game;
  GameManifest? get manifest => _game?.manifest;
  GameView? get view => _view;
  ScoreView get scores => _scores;
  Map<String, Object?> get sharedState => _sharedState;
  RoundResult? get result => _result;
  String? get hostPhase => _hostPhase;

  /// How the phones should be arranged for this round.
  String? get instruction => _instruction;
  String? _instruction;

  /// Every screen's place on the board, in board order, as the game's
  /// `planBoard` decided it. What the placement diagram draws.
  List<PhoneSlice> get slices => _slices;
  List<PhoneSlice> _slices = const [];

  Future<void> connect() async {
    try {
      await _transport.connect();
      _sub = _transport.onMessage.listen(
        _handle,
        onDone: () => _fail(ClientPhase.disconnected, 'Connection closed.'),
        onError: (Object e) => _fail(ClientPhase.disconnected, '$e'),
      );
      // The code first: the host ignores every other message until it has one,
      // and answers `welcome` only once it matches.
      _transport.send({
        'type': ClientMsg.join,
        if (_joinCode != null) 'code': _joinCode,
        'catalog': GameCatalog.fingerprint,
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

  void confirmPlacement() =>
      _transport.send({'type': ClientMsg.confirmPlacement, 'phoneId': _phoneId});

  void sendReset() => _transport.send({'type': ClientMsg.reset});

  /// Forward a touch as raw local pixels.
  ///
  /// Flutter gestures arrive in logical pixels; we scale to *physical* pixels
  /// so the wire format carries no notion of this device's scale factor. The
  /// host converts to world coordinates, since only it knows where this screen
  /// sits.
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

  /// The instant to draw, assembled for the game's own renderer.
  ///
  /// Returns null until there is a layout and something to show — the surface
  /// paints nothing rather than guessing.
  Frame? frameAt(double dtMs) {
    final layout = _layout;
    if (layout == null) return null;

    buffer.advance(dtMs);
    final sampled = buffer.sampleAll();

    final entities = <String, RenderEntity>{};
    for (final entry in sampled.entries) {
      final descriptor = _descriptors[entry.key];
      // An entity we have a transform for but no descriptor is one that
      // spawned in a packet we have not processed yet. Skip it rather than
      // invent a kind for it.
      if (descriptor == null) continue;
      entities[entry.key] = RenderEntity(
        descriptor: descriptor,
        x: entry.value.x,
        y: entry.value.y,
        angle: entry.value.angle,
      );
    }

    return Frame(
      entities: entities,
      sharedState: _sharedState,
      scores: _scores,
      timeMs: buffer.renderTimeMs,
      dt: dtMs / 1000,
      me: layout,
      board: _board ?? layout.board,
      coverage: _coverage ??
          CoverageMap(
            screens: [
              ScreenRect(
                centerX: layout.worldCenterX,
                centerY: layout.worldCenterY,
                width: layout.halfWidth * 2,
                height: layout.halfHeight * 2,
                turnRadians: layout.turnRadians,
              ),
            ],
            board: layout.board,
          ),
    );
  }

  void _handle(Map<String, dynamic> msg) {
    switch (msg['type'] as String?) {
      case HostMsg.welcome:
        if (msg['rejected'] == true) {
          _fail(ClientPhase.rejected, msg['reason'] as String? ?? 'Rejected.');
          return;
        }
        _phoneId = msg['phoneId'] as String;
        _sessionName = msg['sessionName'] as String?;
        _phase = ClientPhase.lobby;
        // Re-send now that we have an id attached.
        _sendCalibration();
        notifyListeners();

      case HostMsg.lobby:
        _lobbyPhones = [
          for (final p in msg['phones'] as List) p as Map<String, dynamic>,
        ];
        _hostPhase = msg['phase'] as String?;
        _adoptGame(msg['game'] as String?);
        // The host went back to setting up: follow it out of the results
        // screen rather than stranding this phone on a stale one.
        if (_phase == ClientPhase.finished && _hostPhase != 'finished') {
          _phase = ClientPhase.lobby;
          _result = null;
        }
        notifyListeners();

      case HostMsg.layout:
        _layout = PhoneLayout.fromJson(msg);
        _coverage =
            CoverageMap.fromJson(msg['coverage'] as Map<String, dynamic>);
        _board = _layout!.board;
        _instruction = msg['instruction'] as String?;
        _slices = [
          for (final s in (msg['slices'] as List?) ?? const [])
            PhoneSlice.fromJson(s as Map<String, dynamic>),
        ];
        _adoptGame(msg['game'] as String?);
        _phase = ClientPhase.placing;
        _result = null;
        _descriptors.clear();
        buffer.clear();
        _prepareView();
        notifyListeners();

      case HostMsg.worldInit:
        _board = WorldRect.fromJson(msg['board'] as Map<String, dynamic>);
        _adoptGame(msg['game'] as String?);
        _descriptors.clear();
        _addDescriptors(msg['entities'] as List?);
        notifyListeners();

      case HostMsg.spawn:
        _addDescriptors(msg['entities'] as List?);

      case HostMsg.despawn:
        for (final id in (msg['ids'] as List?) ?? const []) {
          _descriptors.remove(id as String);
        }

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
        ));
      // No notifyListeners: 60Hz state drives the render loop directly, not
      // the widget tree.

      case HostMsg.shared:
        _sharedState = (msg['state'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{};

      case HostMsg.scores:
        _scores = ScoreView.fromJson((msg['scores'] as List?) ?? const []);
        notifyListeners();

      case HostMsg.outcome:
        _result = RoundResult.fromJson(msg);
        _phase = ClientPhase.finished;
        notifyListeners();

      case HostMsg.pong:
        final sent = (msg['t'] as num).toDouble();
        _rttMs = _clock.elapsedMilliseconds - sent;
    }
  }

  void _addDescriptors(List<dynamic>? entities) {
    if (entities == null) return;
    for (final e in entities) {
      final descriptor =
          EntityDescriptor.fromJson(e as Map<String, dynamic>);
      _descriptors[descriptor.id] = descriptor;
    }
  }

  /// Resolve the game id the host named against this build's catalog.
  ///
  /// A mismatch cannot normally happen — the join handshake compares catalog
  /// fingerprints — so this is the belt to that braces.
  void _adoptGame(String? gameId) {
    if (gameId == null || _game?.manifest.id == gameId) return;
    final game = GameCatalog.byId(gameId);
    if (game == null) {
      _fail(
        ClientPhase.rejected,
        'This phone does not have the game "$gameId". Update the app.',
      );
      return;
    }
    _game = game;
    _disposeView();
  }

  /// Build and load the game's renderer during placement, which is dead time
  /// anyway — people are pushing phones together.
  Future<void> _prepareView() async {
    final game = _game;
    final layout = _layout;
    if (game == null || layout == null || _viewLoading) return;
    if (_view != null) return;

    _viewLoading = true;
    try {
      final view = game.createView(
        ViewContext(phoneId: layout.phoneId, board: layout.board),
      );
      await view.load();
      _view = view;
    } catch (e) {
      _message = 'Could not load ${game.manifest.title}: $e';
    } finally {
      _viewLoading = false;
      notifyListeners();
    }
  }

  void _disposeView() {
    _view?.dispose();
    _view = null;
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _sub?.cancel();
    _disposeView();
    _transport.dispose();
    super.dispose();
  }
}
