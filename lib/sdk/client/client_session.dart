import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/audio_engine.dart';
import '../audio/audio_output.dart';
import '../audio/tone_output.dart';
import '../audio/sounds.dart';
import '../layout/board_links.dart';
import '../model/name_drop_status.dart';
import '../model/table_change.dart';
import '../model/coverage_map.dart';
import '../model/device_metrics.dart';
import '../model/phone_layout.dart';
import '../model/player.dart';
import '../model/player_color.dart';
import '../model/world_rect.dart';
import '../net/protocol.dart';
import '../net/transport.dart';
import '../render/player_animation.dart';
import '../render/player_art.dart';
import '../catalog.dart';
import '../contract/entity.dart';
import '../contract/game.dart';
import '../contract/sim.dart' show OutcomeKind, PhoneSlice;
import '../contract/view.dart';
import '../score/scoreboard.dart';
import 'interruption_watcher.dart';
import 'snapshot_buffer.dart';

enum WipePhase { none, covering, revealing }

enum ClientPhase {
  connecting,
  lobby,
  placing,
  playing,
  finished,
  scoreboard,
  waiting,
  rejected,
  disconnected,
}

class RoundVerdict {
  const RoundVerdict({
    required this.headline,
    required this.line,
    required this.celebrate,
  });

  final String headline;

  final String? line;

  final bool celebrate;
}

class RoundResult {
  const RoundResult({
    required this.won,
    required this.title,
    required this.summary,
    this.kind = OutcomeKind.shared,
    this.winners,
    this.lines,
    this.nextTitle,
    this.nextTagline,
    this.nextInstruction,
    this.runIsOver = false,
  });

  final bool won;
  final String title;
  final String? summary;

  final OutcomeKind kind;

  final Set<String>? winners;

  final Map<String, String>? lines;

  RoundVerdict verdictFor(String? phoneId) {
    final line = phoneId == null ? null : lines?[phoneId];

    switch (kind) {
      case OutcomeKind.contest:
        if (phoneId == null) {
          return const RoundVerdict(
            headline: 'Round over',
            line: null,
            celebrate: false,
          );
        }
        final iWon = winners?.contains(phoneId) ?? false;
        return RoundVerdict(
          headline: iWon ? 'You win!' : 'You lost',
          line: line,
          celebrate: iWon,
        );

      case OutcomeKind.draw:
        return RoundVerdict(headline: 'A draw', line: line, celebrate: false);

      case OutcomeKind.personal:
        return RoundVerdict(
          headline: 'Well played!',
          line: line,
          celebrate: true,
        );

      case OutcomeKind.shared:
        return RoundVerdict(
          headline: won ? 'You win!' : 'Round over',
          line: line,
          celebrate: won,
        );
    }
  }

  final String? nextTitle;
  final String? nextTagline;

  final String? nextInstruction;

  final bool runIsOver;

  bool get hasNext => nextTitle != null;

  static RoundResult fromJson(Map<String, dynamic> j) => RoundResult(
    won: j['won'] as bool? ?? true,
    title: (j['gameTitle'] as String?) ?? 'That round',
    summary: j['summary'] as String?,
    kind: OutcomeKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => OutcomeKind.shared,
    ),
    winners: (j['winners'] as List?)?.map((w) => w as String).toSet(),
    lines: (j['lines'] as Map?)?.map(
      (k, v) => MapEntry(k as String, v as String),
    ),
    nextTitle: j['nextTitle'] as String?,
    nextTagline: j['nextTagline'] as String?,
    nextInstruction: j['nextInstruction'] as String?,
    runIsOver: j['runOver'] as bool? ?? false,
  );
}

class ClientSession extends ChangeNotifier {
  ClientSession({
    required Transport transport,
    required DeviceMetrics metrics,
    String? joinCode,
    String? deviceId,
    PlayerColor? preferredColor,
    this.onColorChosen,
    AudioOutput? audioOutput,
    ToneOutput? toneOutput,
  }) : _transport = transport,
       _metrics = metrics,
       _joinCode = joinCode,
       _deviceId = deviceId,
       _preferredColor = preferredColor,
       audio = AudioEngine(output: audioOutput, tones: toneOutput);

  final Transport _transport;
  DeviceMetrics _metrics;

  final String? _joinCode;

  final String? _deviceId;

  final PlayerColor? _preferredColor;

  final void Function(PlayerColor color)? onColorChosen;

  String? _requestedColorId;

  final buffer = SnapshotBuffer();
  final _clock = Stopwatch()..start();

  late final _interruptions = InterruptionWatcher(_sendInterrupted);

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

  final _descriptors = <String, EntityDescriptor>{};

  Map<String, Object?> _sharedState = const {};
  ScoreView _scores = ScoreView.empty;
  RoundResult? _result;

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

  String? get sessionName => _sessionName;

  MultiscreenGame? get game => _game;
  GameManifest? get manifest => _game?.manifest;
  GameView? get view => _view;
  ScoreView get scores => _scores;
  Map<String, Object?> get sharedState => _sharedState;
  RoundResult? get result => _result;
  String? get hostPhase => _hostPhase;

  TableChange? get tableChange => _tableChange;

  TableChange? _tableChange;

  String? get warning => _warning;
  String? _warning;

  void dismissWarning() {
    _warning = null;
    notifyListeners();
  }

  String? get instruction => _instruction;
  String? _instruction;

  List<PhoneSlice> get slices => _slices;
  List<PhoneSlice> _slices = const [];

  final AudioEngine audio;

  Roster get roster => Roster([
    for (final s in _slices)
      if (s.color != null)
        Player(phoneId: s.phoneId, color: s.color!, label: s.label),
  ], hostPhoneId: _hostPhoneId);

  String? _hostPhoneId;

  bool get showIntro => _showIntro;
  bool _showIntro = false;

  void introFinished() {
    if (!_showIntro) return;
    _showIntro = false;
    notifyListeners();
  }

  bool get isHost => _hostPhoneId != null && _hostPhoneId == _phoneId;

  WipePhase get wipe => _wipe;
  WipePhase _wipe = WipePhase.none;

  bool get inputsFrozen => _wipe == WipePhase.covering;

  Timer? _wipeGuard;

  void _beginWipe() {
    _wipe = WipePhase.covering;

    _wipeGuard?.cancel();
    _wipeGuard = Timer(const Duration(seconds: 6), () {
      if (_wipe != WipePhase.none) revealResult();
    });
  }

  void revealResult() {
    if (_wipe == WipePhase.revealing) return;
    _wipeGuard?.cancel();
    _wipe = WipePhase.revealing;
    _phase = ClientPhase.finished;
    notifyListeners();
  }

  void wipeFinished() {
    if (_wipe == WipePhase.none) return;
    _wipe = WipePhase.none;
    notifyListeners();
  }

  void _cancelWipe() {
    if (_wipe == WipePhase.none) return;
    _wipeGuard?.cancel();
    _wipe = WipePhase.none;
  }

  Player? get me => _phoneId == null ? null : roster.byPhone(_phoneId!);

  List<EdgeMarker> get myLinks => _myLinks;
  List<EdgeMarker> _myLinks = const [];

  List<EdgeMarker> get allLinks => _allLinks;
  List<EdgeMarker> _allLinks = const [];

  Future<void> connect() async {
    try {
      await _transport.connect();
      _sub = _transport.onMessage.listen(
        _handle,
        onDone: () => _fail(ClientPhase.disconnected, 'Connection closed.'),
        onError: (Object e) => _fail(ClientPhase.disconnected, '$e'),
      );

      _transport.send({
        'type': ClientMsg.join,
        if (_joinCode != null) 'code': _joinCode,
        if (_deviceId != null) 'deviceId': _deviceId,
        if (_preferredColor != null) 'preferredColor': _preferredColor.id,
        'catalog': GameCatalog.fingerprint,
      });
      _sendCalibration();
      _pingTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _sendPing(),
      );
      _interruptions.start();
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

  PlayerColor? get myColor => _colorOf(_phoneId);

  PlayerColor? _colorOf(String? phoneId) {
    if (phoneId == null) return null;
    for (final p in _lobbyPhones) {
      if (p['phoneId'] == phoneId) {
        return PlayerPalette.byId(p['color'] as String?);
      }
    }
    return null;
  }

  Set<String> get takenColorIds => {
    for (final p in _lobbyPhones)
      if (p['color'] is String) p['color'] as String,
  };

  void pickColor(PlayerColor color) {
    audio.play(PlayerSounds.happy(color));
    _requestedColorId = color.id;
    _transport.send({
      'type': ClientMsg.pickColor,
      'phoneId': _phoneId,
      'color': color.id,
    });
  }

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

  void _sendInterrupted(Duration held) {
    _transport.send({
      'type': ClientMsg.interrupted,
      'agoMs': held.inMilliseconds,
    });
  }

  void confirmPlacement() {
    final player = me;
    if (player != null) audio.play(player.soundHappy);
    _transport.send({'type': ClientMsg.confirmPlacement, 'phoneId': _phoneId});
  }

  void poke(String phoneId) =>
      _transport.send({'type': ClientMsg.poke, 'phoneId': phoneId});

  void sendReset() => _transport.send({'type': ClientMsg.reset});

  void sendTouch(double logicalX, double logicalY, String phase) {
    if (inputsFrozen) return;

    final dpr = _metrics.devicePixelRatio;
    _transport.send({
      'type': ClientMsg.touch,
      'phoneId': _phoneId,
      'lx': logicalX * dpr,
      'ly': logicalY * dpr,
      'phase': phase,
    });
  }

  Frame? frameAt(double dtMs) {
    final layout = _layout;
    if (layout == null) return null;

    buffer.advance(dtMs);

    audio.pump(buffer.renderTimeMs);
    final sampled = buffer.sampleAll();

    final entities = <String, RenderEntity>{};
    for (final entry in sampled.entries) {
      final descriptor = _descriptors[entry.key];

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
      coverage:
          _coverage ??
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

        _sendCalibration();
        notifyListeners();

      case HostMsg.lobby:
        _warning = msg['warning'] as String?;
        _tableChange = TableChange.fromJson(msg['tableChange']);
        _lobbyPhones = [
          for (final p in msg['phones'] as List) p as Map<String, dynamic>,
        ];
        _hostPhase = msg['phase'] as String?;
        _hostPhoneId = (msg['host'] as String?) ?? _hostPhoneId;
        final chosen = myColor;
        if (_requestedColorId != null && chosen?.id == _requestedColorId) {
          _requestedColorId = null;
          onColorChosen?.call(chosen!);
        }
        _adoptGame(msg['game'] as String?);

        const stale = {
          ClientPhase.placing,
          ClientPhase.playing,
          ClientPhase.finished,
          ClientPhase.waiting,
          ClientPhase.scoreboard,
        };
        if (_hostPhase == 'lobby' && stale.contains(_phase)) {
          _cancelWipe();
          _phase = ClientPhase.lobby;
          _result = null;
        }

        const mine = {ClientPhase.rejected, ClientPhase.disconnected};
        if (_hostPhase == 'scoreboard' && !mine.contains(_phase)) {
          _phase = ClientPhase.scoreboard;
          _result = null;
        }
        notifyListeners();

      case HostMsg.sitOut:
        _cancelWipe();
        _phase = ClientPhase.waiting;

        _result = null;
        notifyListeners();

      case HostMsg.layout:
        _cancelWipe();
        _layout = PhoneLayout.fromJson(msg);
        _coverage = CoverageMap.fromJson(
          msg['coverage'] as Map<String, dynamic>,
        );
        _board = _layout!.board;
        _instruction = msg['instruction'] as String?;
        _showIntro = msg['intro'] == true;
        _slices = [
          for (final s in (msg['slices'] as List?) ?? const [])
            PhoneSlice.fromJson(s as Map<String, dynamic>),
        ];
        final everyLink = [
          for (final l in (msg['links'] as List?) ?? const [])
            EdgeMarker.fromJson(l as Map<String, dynamic>),
        ];
        _allLinks = everyLink;
        _myLinks = everyLink
            .where((l) => l.phoneId == _layout!.phoneId)
            .toList();
        _adoptGame(msg['game'] as String?);
        _phase = ClientPhase.placing;
        _result = null;
        _descriptors.clear();
        buffer.clear();

        PlayerArt.preload([for (final p in roster.players) p.color]);
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

        _warning = null;
        _tableChange = null;
        buffer.clear();
        notifyListeners();

      case HostMsg.state:
        buffer.add(
          Snapshot(
            tick: (msg['tick'] as num).toInt(),
            hostTimeMs: (msg['t'] as num).toDouble(),
            entities: {
              for (final e in msg['entities'] as List)
                (e as Map<String, dynamic>)['id'] as String:
                    EntityState.fromJson(e),
            },
          ),
        );

      case HostMsg.shared:
        _sharedState =
            (msg['state'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{};

      case HostMsg.scores:
        _scores = ScoreView.fromJson((msg['scores'] as List?) ?? const []);
        notifyListeners();

      case HostMsg.outcome:
        _result = RoundResult.fromJson(msg);

        _beginWipe();
        _playVerdict(_result!);
        notifyListeners();

      case HostMsg.sound:
        audio.receive(msg);

      case HostMsg.poke:
        final player = me;
        if (player != null) {
          audio.play(
            msg['mood'] == 'sad' ? player.soundSad : player.soundHappy,
          );
        }

      case HostMsg.pong:
        final sent = (msg['t'] as num).toDouble();
        _rttMs = _clock.elapsedMilliseconds - sent;

      case HostMsg.nameDropSuspected:
        NameDropPref.save(NameDropStatus.waiting);
    }
  }

  void _playVerdict(RoundResult result) {
    final player = me;
    if (player == null || result.kind == OutcomeKind.draw) return;
    final verdict = result.verdictFor(_phoneId);
    audio.play(verdict.celebrate ? player.soundHappy : player.soundSad);
  }

  void _addDescriptors(List<dynamic>? entities) {
    if (entities == null) return;
    for (final e in entities) {
      final descriptor = EntityDescriptor.fromJson(e as Map<String, dynamic>);
      _descriptors[descriptor.id] = descriptor;
    }
  }

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

  Future<void> _prepareView() async {
    final game = _game;
    final layout = _layout;
    if (game == null || layout == null) return;

    if (_viewLoading) {
      _viewWantedAgain = true;
      return;
    }

    final wanted = roster;
    if (_view != null) {
      if (listEquals(_viewRoster, wanted.players)) return;
      _disposeView();
    }

    _viewLoading = true;
    try {
      final characters = await PlayerAnimations.load([
        for (final p in wanted.players) p.color,
      ]);

      final view = game.createView(
        ViewContext(
          phoneId: layout.phoneId,
          board: layout.board,
          characters: characters,
          roster: wanted,
          audio: audio,
        ),
      );
      await view.load();

      if (!identical(_game, game)) {
        view.dispose();
        characters.dispose();
        return;
      }
      _view = view;
      _viewRoster = wanted.players;
      _viewCharacters = characters;
    } catch (e) {
      _message = 'Could not load ${game.manifest.title}: $e';
    } finally {
      _viewLoading = false;
      notifyListeners();
      if (_viewWantedAgain) {
        _viewWantedAgain = false;
        unawaited(_prepareView());
      }
    }
  }

  bool _viewWantedAgain = false;

  List<Player>? _viewRoster;

  PlayerAnimations? _viewCharacters;

  void _disposeView() {
    _view?.dispose();
    _view = null;
    _viewRoster = null;
    _viewCharacters?.dispose();
    _viewCharacters = null;
  }

  @override
  void dispose() {
    _wipeGuard?.cancel();
    _pingTimer?.cancel();
    _interruptions.stop();
    _sub?.cancel();
    _disposeView();
    audio.dispose();
    _transport.dispose();
    super.dispose();
  }
}
