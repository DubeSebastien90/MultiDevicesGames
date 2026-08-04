import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../platform_config.dart';
import '../model/device_metrics.dart';
import '../net/discovery.dart';
import '../net/protocol.dart';
import '../net/transport.dart';
import '../net/websocket_transport.dart';
import '../catalog.dart';
import '../contract/entity.dart';
import '../contract/game.dart';
import '../contract/sim.dart';
import '../layout/board_audit.dart';
import '../layout/board_compiler.dart';
import '../layout/board_plan.dart';
import '../layout/phone_spec.dart';
import '../score/scoreboard.dart';

/// The host's journey through one session.
///
/// [lobby] is about *connecting* — the code, the QR, who is in, and everyone's
/// measurements. [placing] is about the table. There is deliberately no step in
/// between: the game's `planBoard` already decided the arrangement, better than
/// a host squinting at a diagram could.
enum HostPhase { idle, lobby, placing, playing, finished }

/// How a round was started, which decides where it ends.
enum RoundMode {
  /// From the **Play** button: win one and the next begins, forever.
  playlist,

  /// From the games list: play that one, then back to the lobby.
  oneOff,
}

/// One entry in the lobby's list of games.
///
/// The eligibility check is answered once, here, rather than being re-derived
/// by whatever draws the list — so the reason a game is greyed out and the
/// reason it cannot be started are guaranteed to be the same reason.
class GameOffer {
  const GameOffer({
    required this.game,
    required this.playable,
    required this.reason,
  });

  final MultiscreenGame game;

  /// Whether this table can start it right now.
  final bool playable;

  /// Why not, when it does not fit the phone count: 'needs 3+ phones'. Null
  /// when the game itself is fine and only the lobby is not ready.
  final String? reason;

  GameManifest get manifest => game.manifest;
}

/// One connected phone, from the host's point of view.
class PhoneRecord {
  PhoneRecord({required this.link});

  /// Assigned once the join code checks out — an unauthenticated connection
  /// never burns a phone number.
  String phoneId = '';

  final PeerLink link;

  /// False until the right code arrives. Everything this peer says before then
  /// is ignored.
  bool authenticated = false;

  DeviceMetrics? metrics;
  bool confirmed = false;
  bool connected = true;

  /// Round-trip time in ms, from the client's pings. Display only.
  double? rttMs;

  bool get calibrated => metrics != null;
  String get label => metrics?.label ?? phoneId;
}

/// Owns the authoritative world and every connection to it.
///
/// This is the only object that runs a game's simulation. Everything else —
/// including the host's own screen — is a viewport receiving snapshots.
class HostSession extends ChangeNotifier {
  HostSession({
    HostTransport? transport,
    String name = 'My board',
    String? joinCode,
    bool advertise = true,
  }) : _transport = transport ?? WebSocketHostTransport(),
       _name = name,
       _joinCode = joinCode ?? generateJoinCode(),
       _advertise = advertise;

  /// A stranger gets this many wrong guesses before we stop answering them.
  static const int _maxWrongGuesses = 5;
  static const Duration _lockout = Duration(seconds: 30);
  static const Duration _joinDeadline = Duration(seconds: 15);

  final HostTransport _transport;
  final String _name;
  final String _joinCode;
  final bool _advertise;

  final _clock = Stopwatch();
  final _phones = <PhoneRecord>[];
  final _subs = <StreamSubscription<dynamic>>[];
  final _pending = <PhoneRecord, Timer>{};
  final _wrongGuesses = <String, int>{};
  final _lockedOut = <String, DateTime>{};

  /// The session standings, shared by every game.
  final scores = Scoreboard();

  DiscoveryBroadcaster? _beacon;

  HostPhase _phase = HostPhase.idle;
  Uri? _address;
  GameSim? _sim;
  BoardLayout? _layout;
  Timer? _loop;
  String? _warning;

  /// Position in the playlist. Only ever goes up; the catalog wraps.
  int _gameIndex = 0;

  /// Whether the current round chains into the next game or returns to the
  /// lobby. Set when the round starts and never guessed at afterwards.
  RoundMode _mode = RoundMode.playlist;
  MultiscreenGame? _game;
  GameOutcome? _outcome;

  /// Entity ids the clients currently know about, so spawns and despawns can
  /// be diffed out of what the sim reports.
  final _knownEntities = <String>{};
  Map<String, Object?> _lastShared = const {};
  String _lastScoresJson = '';

  int _nextPhoneNumber = 1;
  int _stepCount = 0;
  double _accumulatorMs = 0;
  int _lastClockUs = 0;

  HostPhase get phase => _phase;
  Uri? get address => _address;
  BoardLayout? get layout => _layout;
  String get name => _name;
  String get joinCode => _joinCode;
  String? get warning => _warning;
  GameOutcome? get outcome => _outcome;

  /// The game being set up or played.
  MultiscreenGame? get game => _game;

  String? get qrPayload => _address == null ? null : '$_address#$_joinCode';
  String? get discoveryFailure => _beacon?.failure;

  /// Ordered as the board is laid out.
  List<PhoneRecord> get phones => List.unmodifiable(_phones);

  double get simTimeMs => _stepCount * (1000 / PlatformConfig.simHz);

  /// Set when a game's `planBoard` produced something unusable. The round never
  /// starts, and this says why on the host's own screen.
  String? get planError => _planError;
  String? _planError;

  /// A full record of the last board that was laid out — measurements, plan,
  /// compiled geometry, and the reason every pair of screens was or was not
  /// joined. Readable from any browser at the host's own address.
  String? get lastAudit => _lastAudit;
  String? _lastAudit;

  /// The one-line verdict from that audit, for the host's own screen.
  String? get lastAuditSummary => _lastAuditSummary;
  String? _lastAuditSummary;

  /// The game the playlist would start right now, or null if none fits.
  MultiscreenGame? get upcoming =>
      GameCatalog.playableFrom(_gameIndex, _phones.length);

  bool get canStart =>
      _phase == HostPhase.lobby &&
      _phones.isNotEmpty &&
      _phones.every((p) => p.calibrated && p.connected) &&
      upcoming != null;

  /// Why the Play button is unavailable, for the lobby to say out loud.
  String? get blockedReason {
    if (_phones.isEmpty) return 'Waiting for a phone to connect…';
    if (!_phones.every((p) => p.calibrated && p.connected)) {
      return 'Waiting for every phone to report its size…';
    }
    if (upcoming == null) {
      // Say what would help, not just what is wrong. A parity rule in
      // particular is baffling otherwise: four phones failing when three and
      // five both work needs explaining.
      final sizes = GameCatalog.playableTableSizes();
      final nearest = sizes.where((n) => n > _phones.length).toList();
      final advice = nearest.isEmpty
          ? ''
          : ' Try ${nearest.first} phone(s).';
      return 'No game fits ${_phones.length} phone(s).$advice '
          '${GameCatalog.requirementSummary()}.';
    }
    return null;
  }

  // ------------------------------------------------------------ lifecycle

  Future<Uri> start() async {
    _clock.start();
    final uri = await _transport.start();
    _address = uri;
    _phase = HostPhase.lobby;
    _subs.add(_transport.onPeer.listen(_attachPeer));

    // Make the audit readable from any browser on the same WiFi. The only way
    // to get diagnostics off a phone that is hosting.
    final ws = _transport;
    if (ws is WebSocketHostTransport) {
      ws.diagnostics = () =>
          _lastAudit ?? 'MultiDevicesGame host — no board laid out yet';
    }

    if (_advertise) {
      final beacon = DiscoveryBroadcaster(
        id: '${DateTime.now().microsecondsSinceEpoch}-'
            '${Random().nextInt(1 << 32)}',
        name: _name,
        address: uri,
      );
      await beacon.start();
      _beacon = beacon;
      _updateBeacon();
    }

    notifyListeners();
    return uri;
  }

  /// Adds the host's own screen as a peer. Trusted: this peer is a function
  /// call away, not a socket, so there is nobody to prove anything to.
  void addLocalPeer(PeerLink peer) => _attachPeer(peer, trusted: true);

  void _attachPeer(PeerLink link, {bool trusted = false}) {
    if (_phase == HostPhase.playing || _phase == HostPhase.placing) {
      _reject(link, 'Game already set up. Ask the host to re-calibrate.');
      return;
    }

    final remote = link.debugName;
    final until = _lockedOut[remote];
    if (until != null && DateTime.now().isBefore(until)) {
      _reject(link, 'Too many wrong codes. Wait a moment and try again.');
      return;
    }

    final record = PhoneRecord(link: link);

    // One subscription for the connection's whole life. Splitting it into a
    // "gate" listener and a "session" listener would drop whatever arrived
    // between cancelling the first and attaching the second.
    _subs.add(link.onMessage.listen(
      (msg) => _handleMessage(record, msg),
      onDone: () => _handleDisconnect(record),
      onError: (Object _) => _handleDisconnect(record),
    ));

    if (trusted) {
      _admit(record);
      return;
    }

    _pending[record] = Timer(_joinDeadline, () {
      if (_pending.remove(record) != null) {
        _reject(link, 'No join code was sent.');
      }
    });
  }

  void _handleJoin(PhoneRecord record, Map<String, dynamic> msg) {
    final timer = _pending.remove(record);
    if (timer == null) return;
    timer.cancel();

    // Games run on every device now, so a phone with a different build cannot
    // render what this one is about to send it.
    final catalog = msg['catalog'] as String?;
    if (catalog != null && catalog != GameCatalog.fingerprint) {
      _reject(
        record.link,
        'This phone has a different version of the app. Update both to the '
        'same version.',
      );
      return;
    }

    final offered = (msg['code'] as String?)?.trim() ?? '';
    if (_codeMatches(offered)) {
      _wrongGuesses.remove(record.link.debugName);
      _admit(record);
      return;
    }

    final remote = record.link.debugName;
    final wrong = (_wrongGuesses[remote] ?? 0) + 1;
    _wrongGuesses[remote] = wrong;
    if (wrong >= _maxWrongGuesses) {
      _lockedOut[remote] = DateTime.now().add(_lockout);
      _wrongGuesses.remove(remote);
    }
    _reject(record.link, 'Wrong code.');
  }

  /// Constant-time-ish compare. The timing of a 5-digit string comparison is
  /// not a realistic attack over WiFi, but there is no reason to leak it.
  bool _codeMatches(String offered) {
    if (offered.length != _joinCode.length) return false;
    var diff = 0;
    for (var i = 0; i < offered.length; i++) {
      diff |= offered.codeUnitAt(i) ^ _joinCode.codeUnitAt(i);
    }
    return diff == 0;
  }

  void _admit(PhoneRecord record) {
    record.authenticated = true;
    record.phoneId = 'p${_nextPhoneNumber++}';
    _phones.add(record);
    scores.register(record.phoneId, record.label);
    record.link.send({
      'type': HostMsg.welcome,
      'phoneId': record.phoneId,
      'sessionName': _name,
    });
    _broadcastLobby();
    _broadcastScores();
    _updateBeacon();
    notifyListeners();
  }

  void _reject(PeerLink link, String reason) {
    link.send({'type': HostMsg.welcome, 'rejected': true, 'reason': reason});
    // Long enough for the frame to make it out before the socket shuts.
    Future<void>.delayed(const Duration(milliseconds: 300), link.close);
  }

  void _updateBeacon() => _beacon?.update(
    players: _phones.where((p) => p.connected).length,
    open: _phase == HostPhase.lobby,
  );

  void _handleDisconnect(PhoneRecord record) {
    final pending = _pending.remove(record);
    if (pending != null) {
      pending.cancel();
      return;
    }
    if (!record.authenticated || !record.connected) return;
    record.connected = false;

    if (_phase == HostPhase.lobby) {
      _phones.remove(record);
    } else {
      // Mid-game: leave the world alone (its slice just goes dark) rather than
      // silently rearranging a board people have physically laid out.
      _warning = '${record.label} disconnected — re-calibrate to rebuild the '
          'board.';
    }
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  void _handleMessage(PhoneRecord record, Map<String, dynamic> msg) {
    final type = msg['type'] as String?;

    // Until the code checks out, `join` is the only word this peer knows.
    if (!record.authenticated) {
      if (type == ClientMsg.join) _handleJoin(record, msg);
      return;
    }

    switch (type) {
      case ClientMsg.calibration:
        record.metrics =
            DeviceMetrics.fromJson(msg['metrics'] as Map<String, dynamic>);
        scores.register(record.phoneId, record.label);
        _broadcastLobby();
        notifyListeners();

      case ClientMsg.confirmPlacement:
        if (_phase != HostPhase.placing) return;
        record.confirmed = true;
        _broadcastLobby();
        notifyListeners();
        if (_phones.where((p) => p.connected).every((p) => p.confirmed)) {
          _beginPlay();
        }

      case ClientMsg.touch:
        final sim = _sim;
        final layout = _layout?.forPhone(record.phoneId);
        if (sim == null || layout == null || _phase != HostPhase.playing) {
          return;
        }
        // Clients send raw local pixels; converting them is the host's job,
        // because only the host knows where that screen sits in the world.
        final world = layout.physicalPxToWorld(
          (msg['lx'] as num).toDouble(),
          (msg['ly'] as num).toDouble(),
        );
        sim.onTouch(TouchEvent(
          phoneId: record.phoneId,
          worldX: world.x,
          worldY: world.y,
          phase: msg['phase'] as String,
        ));

      case ClientMsg.reset:
        _sim?.reset();

      case ClientMsg.ping:
        record.link.send({
          'type': HostMsg.pong,
          't': msg['t'],
          'hostT': simTimeMs,
        });
        final rtt = (msg['rtt'] as num?)?.toDouble();
        if (rtt != null) record.rttMs = rtt;
    }
  }

  // ----------------------------------------------------------- the round

  /// Which way the current round was started.
  RoundMode get mode => _mode;

  /// What comes after this round — null for a one-off, or when nothing else
  /// fits the table.
  MultiscreenGame? get nextGame => _mode == RoundMode.oneOff
      ? null
      : GameCatalog.playableFrom(_gameIndex + 1, _phones.length);

  /// One game, then back to the lobby. The games list.
  ///
  /// Everything between the tap and the placement screen happens here, with no
  /// screen in between: the game already knows where the phones go.
  void startGame(MultiscreenGame game) {
    if (!canStart) return;
    if (!game.manifest.fits(_phones.length)) return;
    final index = GameCatalog.playlist
        .indexWhere((g) => g.manifest.id == game.manifest.id);
    if (index < 0) return;
    _mode = RoundMode.oneOff;
    _startGame(index);
  }

  /// The never-ending playlist. The **Play** button.
  void startRound() {
    if (!canStart) return;
    _mode = RoundMode.playlist;
    _startGame(GameCatalog.playableIndexFrom(_gameIndex, _phones.length)!);
  }

  /// Every game, with whether this table can play it. The lobby's list.
  List<GameOffer> get offers => [
    for (final game in GameCatalog.playlist)
      GameOffer(
        game: game,
        playable: canStart && game.manifest.fits(_phones.length),
        reason: game.manifest.fits(_phones.length)
            ? null
            : game.manifest.requirement(),
      ),
  ];

  void _startGame(int index) {
    _gameIndex = index;
    final game = GameCatalog.playlist[index];
    _game = game;
    _outcome = null;
    _planError = null;

    final lobby = LobbyInfo([
      for (final p in _phones)
        PhoneSpec.fromMetrics(p.phoneId, p.metrics!),
    ]);

    final BoardLayout solved;
    final BoardPlan plan;
    try {
      plan = game.planBoard(lobby);
      solved = const BoardCompiler().compile(plan, lobby);
    } on BoardPlanError catch (e) {
      // The game's plan is unusable. Nobody is asked to rearrange a table for
      // a round that cannot run.
      _planError = '${game.manifest.title}: ${e.message}';
      _game = null;
      notifyListeners();
      return;
    }

    // Record what just happened, before anyone is told anything. Four phones on
    // a table produce measurements no synthetic test will guess, and this is
    // how those numbers get read rather than inferred from stripe colours.
    final audit = BoardAudit.of(
      gameId: game.manifest.id,
      lobby: lobby,
      plan: plan,
      board: solved,
    );
    _lastAudit = BoardAudit.toPrettyJson(audit);
    _lastAuditSummary = audit['summary'] as String?;
    debugPrint('=== board audit ===\n$_lastAudit');

    _layout = solved;
    _phase = HostPhase.placing;
    for (final p in _phones) {
      p.confirmed = false;
    }

    for (final phone in _phones) {
      final l = solved.forPhone(phone.phoneId)!;
      phone.link.send({
        'type': HostMsg.layout,
        ...l.toJson(),
        'coverage': solved.coverage.toJson(),
        // The compiled truth about where every phone ended up. The placement
        // diagram is drawn from this, so what people are shown is the layout
        // the game actually chose rather than a guess reconstructed from the
        // lobby's join order.
        'slices': [for (final s in solved.slices) s.toJson()],
        // Coloured stripes marking which edge meets which neighbour. Computed
        // once by the compiler; every phone draws the same answer.
        'links': [for (final l in solved.links) l.toJson()],
        'instruction': solved.instruction,
        ..._gameFields,
      });
    }
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  void _beginPlay() {
    final solved = _layout;
    final game = _game;
    if (solved == null || game == null) return;

    scores.beginRound();
    final sim = game.createSim(solved.contextFor(scores));
    _sim = sim;
    _phase = HostPhase.playing;
    _stepCount = 0;
    _accumulatorMs = 0;
    _lastClockUs = _clock.elapsedMicroseconds;
    _knownEntities.clear();
    _lastShared = const {};

    final initial = sim.entities.toList();
    for (final e in initial) {
      _knownEntities.add(e.id);
    }

    _broadcast({
      'type': HostMsg.worldInit,
      'board': solved.coverage.board.toJson(),
      'entities': [for (final e in initial) e.descriptor.toJson()],
      ..._gameFields,
    });
    _broadcastShared(force: true);
    _broadcastScores(force: true);
    _broadcast({'type': HostMsg.start});

    const period = Duration(microseconds: 1000000 ~/ PlatformConfig.simHz);
    _loop = Timer.periodic(period, (_) => _tick());
    notifyListeners();
  }

  /// Fixed-timestep loop. The timestep is fixed so the sim stays deterministic
  /// and snapshot timestamps land on exact multiples of the step — the client
  /// interpolator gets an evenly spaced timeline to walk along.
  void _tick() {
    final sim = _sim;
    if (sim == null) return;

    const stepMs = 1000 / PlatformConfig.simHz;
    final nowUs = _clock.elapsedMicroseconds;
    // Clamp so a stall (debugger, app backgrounded) cannot trigger a catch-up
    // avalanche of steps.
    final deltaMs = ((nowUs - _lastClockUs) / 1000).clamp(0.0, 100.0);
    _lastClockUs = nowUs;
    _accumulatorMs += deltaMs;

    var stepped = false;
    while (_accumulatorMs >= stepMs) {
      sim.step(1 / PlatformConfig.simHz);
      _accumulatorMs -= stepMs;
      _stepCount++;
      stepped = true;
    }
    if (!stepped) return;

    final entities = sim.entities.toList();
    _broadcastEntityChanges(entities);

    _broadcast({
      'type': HostMsg.state,
      'tick': _stepCount,
      't': simTimeMs,
      'entities': [
        for (final e in entities)
          EntityState(
            id: e.id,
            x: e.x,
            y: e.y,
            angle: e.angle,
            vx: e.vx,
            vy: e.vy,
          ).toJson(),
      ],
    });

    _broadcastShared();
    _broadcastScores();

    final outcome = sim.outcome;
    if (outcome != null) _finishRound(outcome);
  }

  /// Diff the entity set so a game can spawn and despawn freely without ever
  /// sending a message by hand.
  void _broadcastEntityChanges(List<Entity> entities) {
    final current = <String>{};
    final spawned = <Entity>[];
    for (final e in entities) {
      current.add(e.id);
      if (_knownEntities.add(e.id)) spawned.add(e);
    }

    final gone = _knownEntities.difference(current);
    if (gone.isNotEmpty) {
      _knownEntities.removeAll(gone);
      _broadcast({'type': HostMsg.despawn, 'ids': gone.toList()});
    }
    if (spawned.isNotEmpty) {
      _broadcast({
        'type': HostMsg.spawn,
        'entities': [for (final e in spawned) e.descriptor.toJson()],
      });
    }
  }

  /// The round is over. Keep the final frame on screen — a tower mid-collapse
  /// is the reward — and tell everyone what is next.
  void _finishRound(GameOutcome outcome) {
    if (_phase != HostPhase.playing) return;
    _loop?.cancel();
    _loop = null;
    _phase = HostPhase.finished;
    _outcome = outcome;

    final next = nextGame;
    _broadcast({
      'type': HostMsg.outcome,
      'won': outcome.won,
      'summary': outcome.summary,
      ..._gameFields,
      // Present only on a playlist round. Its absence is how every phone knows
      // this one ends at the lobby.
      if (next != null) ...{
        'nextTitle': next.manifest.title,
        'nextTagline': next.manifest.tagline,
        'nextInstruction': _instructionFor(next),
      },
    });
    _broadcastScores(force: true);
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  /// A one-line preview of how the next game wants the phones, without
  /// committing to a full plan.
  String _instructionFor(MultiscreenGame game) {
    try {
      final lobby = LobbyInfo([
        for (final p in _phones)
          if (p.metrics != null) PhoneSpec.fromMetrics(p.phoneId, p.metrics!),
      ]);
      return game.planBoard(lobby).instruction ?? '';
    } on Object {
      return '';
    }
  }

  /// On to the next game in the playlist, which means a new board and so a
  /// fresh trip through placement.
  void advanceToNextGame() {
    if (_phase != HostPhase.finished) return;
    _sim?.dispose();
    _sim = null;
    _layout = null;
    _phones.removeWhere((p) => !p.connected);
    final index =
        GameCatalog.playableIndexFrom(_gameIndex + 1, _phones.length);
    if (index == null) {
      returnToLobby();
      return;
    }
    _startGame(index);
  }

  void resetRound() => _sim?.reset();

  /// Back to the arrangement for the *same* game — the debug panel's
  /// "re-calibrate", for when a measurement was wrong.
  void recalibrate() {
    _loop?.cancel();
    _loop = null;
    _sim?.dispose();
    _sim = null;
    _warning = null;
    _phones.removeWhere((p) => !p.connected);
    for (final p in _phones) {
      p.confirmed = false;
    }
    _startGame(_gameIndex);
  }

  /// All the way back to the connection screen.
  void returnToLobby() {
    _loop?.cancel();
    _loop = null;
    _sim?.dispose();
    _sim = null;
    _layout = null;
    _warning = null;
    _outcome = null;
    _game = null;
    _phones.removeWhere((p) => !p.connected);
    for (final p in _phones) {
      p.confirmed = false;
    }
    _phase = HostPhase.lobby;
    _mode = RoundMode.playlist;
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  void dismissWarning() {
    _warning = null;
    notifyListeners();
  }

  void clearPlanError() {
    _planError = null;
    notifyListeners();
  }

  /// Clear the standings. Nothing else does; leaving a game does not.
  void resetScores() {
    scores.resetAll();
    _broadcastScores(force: true);
    notifyListeners();
  }

  // ------------------------------------------------------------- broadcast

  void _broadcast(Map<String, dynamic> msg) {
    for (final p in _phones) {
      if (p.connected) p.link.send(msg);
    }
  }

  Map<String, dynamic> get _gameFields {
    final game = _game;
    if (game == null) return const {};
    return {
      'game': game.manifest.id,
      'gameTitle': game.manifest.title,
      'gameTagline': game.manifest.tagline,
      'gameGoal': game.manifest.goal,
    };
  }

  void _broadcastLobby() {
    _broadcast({
      'type': HostMsg.lobby,
      'phase': _phase.name,
      ..._gameFields,
      'phones': [
        for (final (i, p) in _phones.indexed)
          {
            'phoneId': p.phoneId,
            'index': i,
            'label': p.label,
            'calibrated': p.calibrated,
            'confirmed': p.confirmed,
            'connected': p.connected,
            if (p.metrics != null) 'widthMm': p.metrics!.widthMm,
            if (p.metrics != null) 'heightMm': p.metrics!.heightMm,
          },
      ],
    });
  }

  /// Only when it changes: this is game state, not a 60 Hz stream.
  void _broadcastShared({bool force = false}) {
    final sim = _sim;
    if (sim == null) return;
    final current = sim.sharedState;
    if (!force && _sameShared(current, _lastShared)) return;
    _lastShared = Map.of(current);
    _broadcast({'type': HostMsg.shared, 'state': current});
  }

  static bool _sameShared(Map<String, Object?> a, Map<String, Object?> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _broadcastScores({bool force = false}) {
    final json = scores.view.toJson();
    final encoded = json.toString();
    if (!force && encoded == _lastScoresJson) return;
    _lastScoresJson = encoded;
    _broadcast({'type': HostMsg.scores, 'scores': json});
  }

  @override
  void dispose() {
    _loop?.cancel();
    for (final t in _pending.values) {
      t.cancel();
    }
    _pending.clear();
    _beacon?.dispose();
    _beacon = null;
    _sim?.dispose();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _transport.dispose();
    super.dispose();
  }
}
