import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../platform_config.dart';
import '../audio/game_audio.dart';
import '../model/table_change.dart';
import '../model/device_identity.dart';
import '../model/device_metrics.dart';
import '../model/player_color.dart';
import '../net/discovery.dart';
import '../net/discovery_stack.dart';
import '../net/protocol.dart';
import '../net/transport.dart';
import '../net/websocket_transport.dart';
import '../catalog.dart';
import '../contract/entity.dart';
import '../contract/game.dart';
import '../contract/sim.dart';
import '../layout/board_compiler.dart';
import '../layout/board_plan.dart';
import '../layout/name_drop_optimizer.dart';
import '../layout/phone_spec.dart';
import '../monetization/premium_status.dart';
import '../score/scoreboard.dart';
import 'name_drop_detector.dart';

enum HostPhase { idle, lobby, placing, playing, finished, scoreboard }

enum RoundMode { playlist, oneOff }

class GameOffer {
  const GameOffer({
    required this.game,
    required this.fitsTable,
    required this.reason,
    required this.chosen,
    required this.isLocked,
    this.lockPending = false,
  });

  final MultiscreenGame game;

  final bool fitsTable;

  final String? reason;

  final bool chosen;

  final bool isLocked;

  final bool lockPending;

  GameManifest get manifest => game.manifest;
}

class PhoneRecord {
  PhoneRecord({required this.link});

  String phoneId = '';

  String? deviceId;

  final PeerLink link;

  bool authenticated = false;

  DeviceMetrics? metrics;
  bool confirmed = false;
  bool connected = true;

  PlayerColor? color;

  double? rttMs;

  bool get calibrated => metrics != null;
  String get label => metrics?.label ?? phoneId;
}

class HostSession extends ChangeNotifier {
  HostSession({
    HostTransport? transport,
    String name = 'My board',
    String? joinCode,
    bool advertise = true,
    PremiumStatus? premium,
    Random? random,
    @visibleForTesting this.simFactory,
  }) : _transport = transport ?? WebSocketHostTransport(),
       _name = name,
       _joinCode = joinCode ?? generateJoinCode(),
       _advertise = advertise,
       _premium = premium,
       _random = random ?? Random();

  static const Duration _joinDeadline = Duration(seconds: 15);

  @visibleForTesting
  final GameSim Function(MultiscreenGame game, BoardContext context)?
  simFactory;

  final HostTransport _transport;
  final String _name;
  final String _joinCode;
  final bool _advertise;

  final Random _random;

  final PremiumStatus? _premium;

  bool get isPremiumUnlocked => _premium?.isPremium ?? false;

  bool get isPremiumSettled => _premium?.isReady ?? true;

  String? get premiumError => _premium?.error;

  final _clock = Stopwatch();
  final _phones = <PhoneRecord>[];
  final _subs = <StreamSubscription<dynamic>>[];
  final _pending = <PhoneRecord, Timer>{};

  final scores = Scoreboard();

  GameAdvertiser? _beacon;
  bool _disposed = false;

  HostPhase _phase = HostPhase.idle;
  Uri? _address;
  GameSim? _sim;
  BoardLayout? _layout;
  Timer? _loop;
  String? _warning;

  bool _introPending = false;

  RoundAudio? _audio;

  int _gameIndex = 0;

  List<MultiscreenGame> _order = GameCatalog.playlist;

  final _skipped = <String>{};

  Set<String>? _runGames;

  Set<String> get _skipping {
    final run = _runGames;
    final base = run == null
        ? _skipped
        : {
            for (final game in GameCatalog.playlist)
              if (!run.contains(game.manifest.id)) game.manifest.id,
          };
    if (isPremiumUnlocked) return base;
    return {
      ...base,
      for (final game in GameCatalog.playlist)
        if (game.manifest.tier == GameTier.premium) game.manifest.id,
    };
  }

  RoundMode _mode = RoundMode.playlist;
  MultiscreenGame? _game;
  GameOutcome? _outcome;

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

  TableChange? get tableChange => _tableChange;
  TableChange? _tableChange;

  void dismissTableChange() {
    _tableChange = null;
    _broadcastLobby();
    notifyListeners();
  }

  GameOutcome? get outcome => _outcome;

  MultiscreenGame? get game => _game;

  String? get qrPayload => _address == null ? null : '$_address#$_joinCode';
  String? get discoveryFailure => _beacon?.failure;

  List<PhoneRecord> get phones => List.unmodifiable(_phones);

  List<PhoneRecord> get _present => [
    for (final p in _phones)
      if (p.connected) p,
  ];

  double get simTimeMs => _stepCount * (1000 / PlatformConfig.simHz);

  String? get planError => _planError;
  String? _planError;

  Set<(String, String)> _dangerPairs = const {};

  final _nameDrop = NameDropDetector();

  MultiscreenGame? get upcoming => GameCatalog.playableFrom(
    _gameIndex,
    _present.length,
    skipping: _skipping,
    order: _order,
  );

  bool get canStart =>
      _phase == HostPhase.lobby &&
      _present.isNotEmpty &&
      _present.every((p) => p.calibrated) &&
      upcoming != null;

  String? get blockedReason {
    if (_present.isEmpty) return 'Waiting for a phone to connect…';
    if (!_present.every((p) => p.calibrated)) {
      return 'Waiting for every phone to report its size…';
    }
    if (chosenGames.isEmpty) {
      return 'No games are ticked. Tap the gear to choose some.';
    }
    if (upcoming == null) {
      final sizes = GameCatalog.playableTableSizes(skipping: _skipping);
      final nearest = sizes.where((n) => n > _present.length).toList();
      final advice = nearest.isEmpty ? '' : ' Try ${nearest.first} phone(s).';
      return 'No ticked game fits ${_present.length} phone(s).$advice '
          '${GameCatalog.requirementSummary(skipping: _skipping)}.';
    }
    return null;
  }

  List<MultiscreenGame> get chosenGames => [
    for (final game in GameCatalog.playlist)
      if (!_skipped.contains(game.manifest.id)) game,
  ];

  List<MultiscreenGame> get runningOrder {
    final skipping = _skipping;
    return [
      for (final game in GameCatalog.playlist)
        if (!skipping.contains(game.manifest.id) &&
            game.manifest.fits(_present.length))
          game,
    ];
  }

  List<GameOffer> get offers => [
    for (final game in GameCatalog.playlist)
      GameOffer(
        game: game,
        fitsTable: game.manifest.fits(_present.length),
        reason: game.manifest.fits(_present.length)
            ? null
            : game.manifest.requirement(),
        chosen: !_skipping.contains(game.manifest.id),
        isLocked:
            game.manifest.isPremium && !isPremiumUnlocked && isPremiumSettled,
        lockPending:
            game.manifest.isPremium && !isPremiumUnlocked && !isPremiumSettled,
      ),
  ];

  void chooseGame(MultiscreenGame game, {required bool chosen}) {
    if (!isPremiumUnlocked) return;
    final changed = chosen
        ? _skipped.remove(game.manifest.id)
        : _skipped.add(game.manifest.id);
    if (changed) notifyListeners();
  }

  void chooseAllGames() {
    if (!isPremiumUnlocked) return;
    if (_skipped.isEmpty) return;
    _skipped.clear();
    notifyListeners();
  }

  void chooseNoGames() {
    if (!isPremiumUnlocked) return;
    if (_skipped.length == GameCatalog.playlist.length) return;
    _skipped
      ..clear()
      ..addAll([for (final g in GameCatalog.playlist) g.manifest.id]);
    notifyListeners();
  }

  Future<Uri> start() async {
    _clock.start();
    final uri = await _transport.start();

    if (_disposed) return uri;
    _address = uri;
    _phase = HostPhase.lobby;
    _subs.add(_transport.onPeer.listen(_attachPeer));

    if (_advertise) {
      final beacon = _beacon = createGameAdvertiser(
        id:
            '${DateTime.now().microsecondsSinceEpoch}-'
            '${Random().nextInt(1 << 32)}',
        name: _name,
        address: uri,
      );
      _updateBeacon();
      await beacon.start();
      if (_disposed) return uri;
    }

    notifyListeners();
    return uri;
  }

  PhoneRecord? _localRecord;

  String? get hostPhoneId => _localRecord?.phoneId;

  void addLocalPeer(PeerLink peer, {PlayerColor? preferredColor}) {
    _localRecord = _attachPeer(
      peer,
      trusted: true,
      preferredColor: preferredColor,
    );
  }

  PhoneRecord _attachPeer(
    PeerLink link, {
    bool trusted = false,
    PlayerColor? preferredColor,
  }) {
    final record = PhoneRecord(link: link);

    _subs.add(
      link.onMessage.listen(
        (msg) => _handleMessage(record, msg),
        onDone: () => _handleDisconnect(record),
        onError: (Object _) => _handleDisconnect(record),
      ),
    );

    if (trusted) {
      _admit(record, preferredColor: preferredColor);
      return record;
    }

    _pending[record] = Timer(_joinDeadline, () {
      if (_pending.remove(record) != null) {
        _reject(link, 'That phone never finished joining.');
      }
    });
    return record;
  }

  void _handleJoin(PhoneRecord record, Map<String, dynamic> msg) {
    final timer = _pending.remove(record);
    if (timer == null) return;
    timer.cancel();

    final catalog = msg['catalog'] as String?;
    if (catalog != null && catalog != GameCatalog.fingerprint) {
      _reject(
        record.link,
        'This phone has a different version of the app. Update both to the '
        'same version.',
      );
      return;
    }

    final deviceId = msg['deviceId'] as String?;

    if (!_openToStrangers && _seatFor(deviceId) == null) {
      _reject(
        record.link,
        'That game has already started. Ask the host to re-calibrate.',
      );
      return;
    }

    final seat = _seatFor(deviceId);
    if (seat?.color == null &&
        PlayerPalette.firstFree(_takenColorIds()) == null) {
      _reject(record.link, 'The table is full.');
      return;
    }

    _admit(
      record,
      deviceId: deviceId,
      preferredColor: PlayerPalette.byId(msg['preferredColor'] as String?),
    );
  }

  PhoneRecord? _seatFor(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) return null;
    for (final p in _phones) {
      if (p.deviceId == deviceId && !p.connected) return p;
    }
    return null;
  }

  void _admit(
    PhoneRecord record, {
    String? deviceId,
    PlayerColor? preferredColor,
  }) {
    record.authenticated = true;
    record.deviceId = deviceId;

    final returning = _seatFor(deviceId);
    if (returning != null) {
      record.phoneId = returning.phoneId;

      record.color = returning.color ?? _seatColour(preferredColor);
      record.metrics ??= returning.metrics;
      _phones[_phones.indexOf(returning)] = record;
    } else {
      record.phoneId = 'p${_nextPhoneNumber++}';

      record.color = _seatColour(preferredColor);
      _phones.add(record);
    }

    scores.register(record.phoneId, record.label);
    record.link.send({
      'type': HostMsg.welcome,
      'phoneId': record.phoneId,
      'sessionName': _name,
    });
    if (returning != null && _phase == HostPhase.playing) {
      final sim = _sim;
      if (sim is PlayerPresence) {
        (sim as PlayerPresence).onPlayerReturned(record.phoneId);
      }
    }

    if (returning != null && _phase == HostPhase.placing) {
      _broadcastLobby();
      _broadcastScores();
      _updateBeacon();
      _layOutAgain(because: '${record.label} came back');
      notifyListeners();
      return;
    }

    _catchUp(record);
    _broadcastLobby();
    _broadcastScores();
    _updateBeacon();
    notifyListeners();
  }

  void _catchUp(PhoneRecord record) {
    final solved = _layout;
    if (solved == null || _phase == HostPhase.lobby) return;

    final mine = solved.forPhone(record.phoneId);
    if (mine == null || _phase == HostPhase.finished) {
      record.link.send({'type': HostMsg.sitOut});
      return;
    }

    record.link.send({
      'type': HostMsg.layout,
      ...mine.toJson(),
      'coverage': solved.coverage.toJson(),
      'slices': [for (final s in solved.slices) s.toJson()],
      'links': [for (final l in solved.links) l.toJson()],
      'instruction': solved.instruction,
      ..._gameFields,
    });

    final sim = _sim;
    if (sim == null) return;

    record.link.send({
      'type': HostMsg.worldInit,
      'board': solved.coverage.board.toJson(),
      'entities': [for (final e in sim.entities) e.descriptor.toJson()],
      ..._gameFields,
    });
    record.link.send({'type': HostMsg.shared, 'state': sim.sharedState});
    record.link.send({'type': HostMsg.scores, 'scores': scores.view.toJson()});
    record.link.send({'type': HostMsg.start});
  }

  void _reject(PeerLink link, String reason) {
    link.send({'type': HostMsg.welcome, 'rejected': true, 'reason': reason});

    Future<void>.delayed(const Duration(milliseconds: 300), link.close);
  }

  PlayerColor? _seatColour(PlayerColor? preferred) {
    final taken = _takenColorIds().toSet();
    if (preferred != null && !taken.contains(preferred.id)) return preferred;
    return PlayerPalette.firstFree(taken);
  }

  void _releaseAwayColours() {
    for (final p in _phones) {
      if (!p.connected) p.color = null;
    }
  }

  Iterable<String> _takenColorIds() sync* {
    for (final p in _phones) {
      final c = p.color;
      if (c != null) yield c.id;
    }
  }

  void _handlePickColour(PhoneRecord record, String? colorId) {
    if (_phase != HostPhase.lobby) return;

    final wanted = PlayerPalette.byId(colorId);
    if (wanted == null) return;
    if (record.color?.id == wanted.id) return;

    for (final other in _phones) {
      if (other != record && other.color?.id == wanted.id) return;
    }

    record.color = wanted;
    _broadcastLobby();
    notifyListeners();
  }

  bool get _openToStrangers =>
      _phase == HostPhase.lobby || _phase == HostPhase.scoreboard;

  void _updateBeacon() => _beacon?.update(
    players: _phones.where((p) => p.connected).length,
    open: _openToStrangers,
    rejoinable: [
      for (final p in _phones)
        if (!p.connected && p.deviceId != null)
          DeviceIdentity.fingerprint(p.deviceId!),
    ],
  );

  void _handleDisconnect(PhoneRecord record) {
    final pending = _pending.remove(record);
    if (pending != null) {
      pending.cancel();
      return;
    }
    if (!record.authenticated || !record.connected) return;
    record.connected = false;
    if (_openToStrangers) _releaseAwayColours();

    if (_phase != HostPhase.lobby) {
      if (_phase == HostPhase.placing) {
        _layoutAgainWithoutThem(record);
      } else {
        _warning =
            '${record.label} disconnected — re-calibrate to rebuild the '
            'board.';
        _tellTheGameSomebodyLeft(record);
      }
    }
    _broadcastLobby();

    _broadcastScores();
    _updateBeacon();
    notifyListeners();
  }

  void _layoutAgainWithoutThem(PhoneRecord who) {
    if (_layout?.forPhone(who.phoneId) == null) {
      _beginPlayIfEveryoneIsInPlace();
      return;
    }

    _layOutAgain(because: '${who.label} left');
  }

  void _layOutAgain({required String because}) {
    final game = _game;

    final index = game != null && game.manifest.fits(_present.length)
        ? _gameIndex
        : GameCatalog.playableIndexFrom(
            _gameIndex + 1,
            _present.length,
            skipping: _skipping,
            order: _order,
          );

    if (index == null) {
      _tableChange = TableChange(who: because);
      _planError =
          '$because — nothing left in the playlist fits '
          '${_present.length} phone(s). '
          '${GameCatalog.requirementSummary(skipping: _skipping)}.';
      _game = null;
      _layout = null;
      _runGames = null;
      _phase = HostPhase.lobby;
      _releaseAwayColours();
      _broadcastLobby();
      notifyListeners();
      return;
    }

    _tableChange = TableChange(
      who: because,
      nextGame: _order[index].manifest.title,
    );
    _startGame(index);
  }

  void _beginPlayIfEveryoneIsInPlace() {
    if (_phase != HostPhase.placing) return;
    final board = _layout;
    if (board == null) return;

    final onTheBoard = [
      for (final p in _phones)
        if (p.connected && board.forPhone(p.phoneId) != null) p,
    ];
    if (onTheBoard.isEmpty) return;
    if (onTheBoard.every((p) => p.confirmed)) _beginPlay();
  }

  void _tellTheGameSomebodyLeft(PhoneRecord record) {
    final sim = _sim;
    if (sim == null || _phase != HostPhase.playing) return;

    if (sim is PlayerPresence) {
      (sim as PlayerPresence).onPlayerLeft(record.phoneId);
      return;
    }
    _finishRound(GameOutcome.draw(summary: '${record.label} dropped out'));
  }

  void _handleMessage(PhoneRecord record, Map<String, dynamic> msg) {
    final type = msg['type'] as String?;

    if (!record.authenticated) {
      if (type == ClientMsg.join) _handleJoin(record, msg);
      return;
    }

    switch (type) {
      case ClientMsg.calibration:
        record.metrics = DeviceMetrics.fromJson(
          msg['metrics'] as Map<String, dynamic>,
        );

        scores.register(record.phoneId, record.label);
        _broadcastLobby();
        _broadcastScores();
        notifyListeners();

      case ClientMsg.pickColor:
        _handlePickColour(record, msg['color'] as String?);

      case ClientMsg.confirmPlacement:
        if (_phase != HostPhase.placing) return;
        record.confirmed = true;
        _broadcastLobby();
        notifyListeners();
        _beginPlayIfEveryoneIsInPlace();

      case ClientMsg.touch:
        final sim = _sim;
        final layout = _layout?.forPhone(record.phoneId);
        if (sim == null || layout == null || _phase != HostPhase.playing) {
          return;
        }

        final world = layout.physicalPxToWorld(
          (msg['lx'] as num).toDouble(),
          (msg['ly'] as num).toDouble(),
        );
        sim.onTouch(
          TouchEvent(
            phoneId: record.phoneId,
            worldX: world.x,
            worldY: world.y,
            phase: msg['phase'] as String,
          ),
        );

      case ClientMsg.interrupted:
        _handleInterrupted(record, msg);

      case ClientMsg.poke:
        _handlePoke(record, msg['phoneId'] as String?);

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

  void _handleInterrupted(PhoneRecord record, Map<String, dynamic> msg) {
    if (_layout == null) return;

    final agoMs = (msg['agoMs'] as num?)?.toInt();
    if (agoMs == null) return;

    final pair = _nameDrop.report(
      record.phoneId,
      Duration(milliseconds: agoMs),
      _dangerPairs,
    );
    if (pair == null) return;

    for (final phoneId in [pair.$1, pair.$2]) {
      _phoneById(phoneId)?.link.send({'type': HostMsg.nameDropSuspected});
    }
  }

  void _handlePoke(PhoneRecord from, String? phoneId) {
    if (_phase != HostPhase.placing) return;
    if (phoneId == null || phoneId == from.phoneId) return;

    final target = _phoneById(phoneId);
    if (target == null) return;

    target.link.send({
      'type': HostMsg.poke,
      'mood': _poking.nextBool() ? 'happy' : 'sad',
    });
  }

  final _poking = Random();

  PhoneRecord? _phoneById(String phoneId) {
    for (final p in _phones) {
      if (p.connected && p.phoneId == phoneId) return p;
    }
    return null;
  }

  RoundMode get mode => _mode;

  MultiscreenGame? get nextGame => _mode == RoundMode.oneOff
      ? null
      : GameCatalog.playableFrom(
          _gameIndex + 1,
          _present.length,
          skipping: _skipping,
          order: _order,
        );

  bool get runIsOver => _mode == RoundMode.playlist && nextGame == null;

  @visibleForTesting
  void startGame(MultiscreenGame game) {
    if (!canStart) return;
    if (!game.manifest.fits(_present.length)) return;

    if (!_mayStart(game)) return;
    final index = _order.indexWhere((g) => g.manifest.id == game.manifest.id);
    if (index < 0) return;
    _mode = RoundMode.oneOff;

    _runGames = null;
    _startGame(index);
  }

  void startRound() {
    if (!canStart) return;
    _mode = RoundMode.playlist;

    _runGames = {for (final game in runningOrder) game.manifest.id};

    _order = List.of(GameCatalog.playlist)..shuffle(_random);

    _introPending = true;

    _startGame(
      GameCatalog.playableIndexFrom(
        0,
        _present.length,
        skipping: _skipping,
        order: _order,
      )!,
    );
  }

  bool _mayStart(MultiscreenGame game) =>
      !game.manifest.isPremium || isPremiumUnlocked;

  void _startGame(int index) {
    final game = _order[index];

    if (!_mayStart(game)) return;

    _gameIndex = index;
    _game = game;
    _outcome = null;
    _planError = null;

    final lobby = LobbyInfo([
      for (final p in _present)
        PhoneSpec.fromMetrics(p.phoneId, p.metrics!, color: p.color),
    ]);

    final BoardLayout solved;
    final BoardPlan plan;
    try {
      final rawPlan = game.planBoard(lobby);
      plan = game.manifest.skipNameDropOptimizer
          ? rawPlan
          : NameDropOptimizer.optimize(rawPlan, lobby);
      solved = const BoardCompiler().compile(plan, lobby);
    } on BoardPlanError catch (e) {
      _planError = '${game.manifest.title}: ${e.message}';
      _game = null;
      _layout = null;
      _runGames = null;
      _phase = HostPhase.lobby;
      _releaseAwayColours();
      _broadcastLobby();
      notifyListeners();
      return;
    }

    _dangerPairs = NameDropOptimizer.dangerousPairs(plan, lobby);
    _nameDrop.clear();

    _layout = solved;
    _phase = HostPhase.placing;
    for (final p in _phones) {
      p.confirmed = false;
    }

    for (final phone in _present) {
      final l = solved.forPhone(phone.phoneId)!;
      phone.link.send({
        'type': HostMsg.layout,
        ...l.toJson(),
        'coverage': solved.coverage.toJson(),
        'slices': [for (final s in solved.slices) s.toJson()],
        'links': [for (final l in solved.links) l.toJson()],
        'instruction': solved.instruction,
        if (_introPending) 'intro': true,
        ..._gameFields,
      });
    }
    _introPending = false;
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  void _beginPlay() {
    final solved = _layout;
    final game = _game;
    if (solved == null || game == null) return;

    scores.beginRound();

    final audio = RoundAudio();
    final GameSim sim;
    try {
      final context = solved.contextFor(
        scores,
        audio: audio,
        hostPhoneId: hostPhoneId,
      );
      sim = simFactory?.call(game, context) ?? game.createSim(context);
    } catch (e) {
      _planError = '${game.manifest.title}: $e';
      _phase = HostPhase.lobby;
      _releaseAwayColours();
      _game = null;
      _layout = null;
      _runGames = null;
      _broadcastLobby();
      notifyListeners();
      return;
    }
    _sim = sim;
    _audio = audio;

    _tableChange = null;

    _warning = null;
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

    _flushAudio();

    const period = Duration(microseconds: 1000000 ~/ PlatformConfig.simHz);
    _loop = Timer.periodic(period, (_) => _tick());
    notifyListeners();
  }

  void _tick() {
    final sim = _sim;
    if (sim == null) return;

    const stepMs = 1000 / PlatformConfig.simHz;
    final nowUs = _clock.elapsedMicroseconds;

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

    _flushAudio();

    final outcome = sim.outcome;
    if (outcome != null) _finishRound(outcome);
  }

  void _flushAudio() {
    final audio = _audio;
    if (audio == null || !audio.hasPending) return;

    final at = simTimeMs;
    for (final command in audio.drain()) {
      final msg = {'type': HostMsg.sound, ...command.toJson(at)};
      if (command.isBroadcast) {
        _broadcast(msg);
        continue;
      }
      final phoneId = command.phoneId;
      if (phoneId == null) {
        _localRecord?.link.send(msg);
      } else {
        _phoneById(phoneId)?.link.send(msg);
      }
    }
  }

  void _silenceRound() {
    final audio = _audio;
    if (audio == null) return;
    audio.stopRoundSounds();
    _flushAudio();
    _audio = null;
  }

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

  void _warnAboutUnknownPhones(GameOutcome outcome) {
    final known = {for (final p in _present) p.phoneId};
    final named = <String>{...?outcome.winners, ...?outcome.lines?.keys};
    final strangers = named.difference(known);
    if (strangers.isEmpty) return;

    _warning =
        '${_game?.manifest.title ?? 'That game'} ended naming phones '
        'that are not here: ${strangers.join(', ')}. Outcomes are keyed by '
        'phoneId.';
    debugPrint('[outcome] $_warning');
  }

  void _finishRound(GameOutcome outcome) {
    if (_phase != HostPhase.playing) return;
    _loop?.cancel();
    _loop = null;
    _phase = HostPhase.finished;
    _outcome = outcome;

    _warnAboutUnknownPhones(outcome);

    final next = nextGame;
    _broadcast({
      'type': HostMsg.outcome,
      'kind': outcome.kind.name,
      'won': outcome.won,
      'summary': outcome.summary,
      if (outcome.winners != null) 'winners': outcome.winners!.toList(),
      if (outcome.lines != null) 'lines': outcome.lines,
      ..._gameFields,
      'runOver': runIsOver,
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

  void advanceToNextGame() {
    if (_phase != HostPhase.finished) return;
    _silenceRound();
    _sim?.dispose();
    _sim = null;
    _layout = null;

    final index = GameCatalog.playableIndexFrom(
      _gameIndex + 1,
      _present.length,
      skipping: _skipping,
      order: _order,
    );
    if (index == null) {
      showScoreboard();
      return;
    }
    _startGame(index);
  }

  void showScoreboard() {
    if (_phase == HostPhase.scoreboard) return;
    _loop?.cancel();
    _loop = null;
    _silenceRound();
    _sim?.dispose();
    _sim = null;
    _layout = null;
    _warning = null;

    _tableChange = null;
    _outcome = null;
    _game = null;

    _runGames = null;

    for (final p in _phones) {
      p.confirmed = false;
    }
    _phase = HostPhase.scoreboard;
    _releaseAwayColours();

    _broadcastScores(force: true);
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  void resetRound() {
    _sim?.reset();
    _audio?.stopRoundSounds();
    _flushAudio();
  }

  void recalibrate() {
    _loop?.cancel();
    _loop = null;
    _silenceRound();
    _sim?.dispose();
    _sim = null;
    _warning = null;
    _tableChange = null;

    for (final p in _phones) {
      p.confirmed = false;
    }
    _startGame(_gameIndex);
  }

  void returnToLobby() {
    _loop?.cancel();
    _loop = null;
    _silenceRound();
    _sim?.dispose();
    _sim = null;
    _layout = null;
    _warning = null;

    _tableChange = null;
    _outcome = null;
    _game = null;

    for (final p in _phones) {
      p.confirmed = false;
    }
    _phase = HostPhase.lobby;
    _releaseAwayColours();
    _mode = RoundMode.playlist;

    _gameIndex = 0;
    _order = GameCatalog.playlist;

    _runGames = null;
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

  void resetScores() {
    scores.resetAll();
    _broadcastScores(force: true);
    notifyListeners();
  }

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
      if (hostPhoneId != null) 'host': hostPhoneId,
      if (_warning != null) 'warning': _warning,
      if (_tableChange != null) 'tableChange': _tableChange!.toJson(),
      ..._gameFields,
      'phones': [
        for (final (i, p) in _phones.indexed)
          {
            'phoneId': p.phoneId,
            'index': i,
            'label': p.label,
            if (p.color != null) 'color': p.color!.id,
            'calibrated': p.calibrated,
            'confirmed': p.confirmed,
            'connected': p.connected,
            if (p.metrics != null) 'widthMm': p.metrics!.widthMm,
            if (p.metrics != null) 'heightMm': p.metrics!.heightMm,
          },
      ],
    });
  }

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
    _disposed = true;
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
