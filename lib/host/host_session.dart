import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../game/game_config.dart';
import '../game/mini_game.dart';
import '../model/arrangement.dart';
import '../model/device_metrics.dart';
import '../net/discovery.dart';
import '../net/protocol.dart';
import '../net/transport.dart';
import '../net/websocket_transport.dart';
import 'game_catalog.dart';
import 'layout_solver.dart';

/// The host's journey through one session.
///
/// [lobby] is about *connecting* — the code, the QR, who is in. [arranging] is
/// about the *table* — which minigame is next and where each phone physically
/// goes. Keeping them apart is what lets a second minigame with a different
/// board shape exist: the lobby is entered once, the arrangement screen once
/// per round.
enum HostPhase { idle, lobby, arranging, placing, playing, won }

/// One connected phone, from the host's point of view.
class PhoneRecord {
  PhoneRecord({required this.link});

  /// Assigned once the join code checks out — an unauthenticated connection
  /// never burns a phone number, so the first real joiner is always `p2`.
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
/// This is the only object in the app that runs physics. Everything else —
/// including the host's own screen — is a viewport that receives snapshots.
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
  /// With 100 000 codes and a 30-second penalty, guessing your way in takes
  /// weeks — while a friend fat-fingering a digit is barely inconvenienced.
  static const int _maxWrongGuesses = 5;
  static const Duration _lockout = Duration(seconds: 30);

  /// How long a connection may sit there without proving itself.
  static const Duration _joinDeadline = Duration(seconds: 15);

  final HostTransport _transport;
  final String _name;
  final String _joinCode;
  final bool _advertise;

  final _clock = Stopwatch();
  final _phones = <PhoneRecord>[];
  final _subs = <StreamSubscription<dynamic>>[];

  /// Connections that have not sent a valid code yet.
  final _pending = <PhoneRecord, Timer>{};

  /// Wrong-code counters, keyed by remote address.
  final _wrongGuesses = <String, int>{};
  final _lockedOut = <String, DateTime>{};

  DiscoveryBroadcaster? _beacon;

  HostPhase _phase = HostPhase.idle;
  Uri? _address;
  MiniGameSim? _sim;
  BoardLayout? _layout;
  Timer? _loop;
  String? _warning;

  /// Position in the playlist. It only ever goes up; the catalog wraps.
  int _gameIndex = 0;

  int _nextPhoneNumber = 1;
  int _stepCount = 0;
  double _accumulatorMs = 0;
  int _lastClockUs = 0;

  HostPhase get phase => _phase;
  Uri? get address => _address;
  BoardLayout? get layout => _layout;

  /// The minigame being set up or played right now.
  MiniGameDef get game => GameCatalog.at(_gameIndex);

  /// What comes after a win. Shown on the victory screen so people know which
  /// way to turn their phones next.
  MiniGameDef get nextGame => GameCatalog.at(_gameIndex + 1);

  /// Live score for the current round, when the game keeps one.
  GameProgress? get progress => _sim?.progress;

  /// What this game is called on other phones' join lists.
  String get name => _name;

  /// The secret that lets a phone in. Shown on the host's screen only.
  String get joinCode => _joinCode;

  /// The QR payload: address plus code, so scanning skips the keypad.
  String? get qrPayload =>
      _address == null ? null : '$_address#$_joinCode';

  /// Non-null when the game could not be advertised — the network blocked the
  /// beacon, or the platform refused the socket. Hosting still works; joiners
  /// use the QR or type the address.
  String? get discoveryFailure => _beacon?.failure;

  /// Ordered left-to-right; this order *is* the physical arrangement.
  List<PhoneRecord> get phones => List.unmodifiable(_phones);

  String? get warning => _warning;

  /// Sim time in ms — the timeline every snapshot is stamped with.
  double get simTimeMs => _stepCount * (1000 / GameConfig.simHz);

  /// The lobby's only exit: at least one phone, all of them reporting a size.
  bool get canStartArranging =>
      _phase == HostPhase.lobby &&
      _phones.isNotEmpty &&
      _phones.every((p) => p.calibrated && p.connected);

  bool get canPlacePhones =>
      _phase == HostPhase.arranging &&
      _phones.isNotEmpty &&
      _phones.every((p) => p.calibrated && p.connected);

  // ------------------------------------------------------------ lifecycle

  Future<Uri> start() async {
    _clock.start();
    final uri = await _transport.start();
    _address = uri;
    _phase = HostPhase.lobby;
    _subs.add(_transport.onPeer.listen(_attachPeer));

    if (_advertise) {
      final beacon = DiscoveryBroadcaster(
        // Random per session: two games with the same name stay distinct in a
        // joiner's list, and the id reveals nothing about the code.
        id: '${DateTime.now().microsecondsSinceEpoch}-'
            '${Random().nextInt(1 << 32)}',
        name: _name,
        address: uri,
      );
      // Never blocks hosting: if the beacon cannot start, the game is simply
      // unlisted and joiners fall back to the QR or the typed address.
      await beacon.start();
      _beacon = beacon;
      _updateBeacon();
    }

    notifyListeners();
    return uri;
  }

  /// Adds the host's own screen as a peer. It then goes through the identical
  /// handshake, layout and interpolation path as any remote phone — which is
  /// what keeps every screen on one shared timeline.
  ///
  /// Trusted: this peer is a function call away, not a socket, so there is
  /// nobody to prove anything to.
  void addLocalPeer(PeerLink peer) => _attachPeer(peer, trusted: true);

  void _attachPeer(PeerLink link, {bool trusted = false}) {
    if (_phase == HostPhase.playing || _phase == HostPhase.placing) {
      // Joining mid-game would invalidate the board everyone already placed
      // themselves for. Turn them away with an explanation instead.
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

    // A connection that never sends a code is either a port scanner or a
    // crashed client. Either way it should not hold a slot open forever.
    _pending[record] = Timer(_joinDeadline, () {
      if (_pending.containsKey(record)) {
        _pending.remove(record);
        _reject(link, 'No join code was sent.');
      }
    });
  }

  /// Checks the code and either lets the phone in or shows it the door.
  void _handleJoin(PhoneRecord record, Map<String, dynamic> msg) {
    final timer = _pending.remove(record);
    if (timer == null) return; // Not waiting on this one; ignore a repeat.
    timer.cancel();

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
    record.link.send({
      'type': HostMsg.welcome,
      'phoneId': record.phoneId,
      'gameName': _name,
    });
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  void _reject(PeerLink link, String reason) {
    link.send({
      'type': HostMsg.welcome,
      'rejected': true,
      'reason': reason,
    });
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
      // Dropped before it ever got in; there is nothing to clean up.
      pending.cancel();
      return;
    }
    if (!record.authenticated) return;
    if (!record.connected) return;
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
        if (sim == null || layout == null || _phase != HostPhase.playing) return;
        // Clients send raw local pixels; converting them is the host's job,
        // because only the host knows where that screen sits in the world.
        final world = layout.physicalPxToWorld(
          (msg['lx'] as num).toDouble(),
          (msg['ly'] as num).toDouble(),
        );
        sim.onTouch(
          phoneId: record.phoneId,
          worldX: world.x,
          worldY: world.y,
          phase: msg['phase'] as String,
        );

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

  // ----------------------------------------------------------- arrangement

  /// Swaps a phone with its neighbour. The list order is the physical strip, so
  /// this is how you say "actually, that phone is on the left".
  void movePhone(int index, int delta) {
    final target = index + delta;
    if (_phase != HostPhase.arranging) return;
    if (index < 0 || index >= _phones.length) return;
    if (target < 0 || target >= _phones.length) return;
    final p = _phones.removeAt(index);
    _phones.insert(target, p);
    _broadcastLobby();
    notifyListeners();
  }

  /// Leaves the lobby for the table: the connection details are done with, and
  /// what matters now is which game is next and where the phones go.
  void startArranging() {
    if (!canStartArranging) return;
    _phase = HostPhase.arranging;
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  /// Back to the connection screen, to let one more friend in.
  void backToLobby() {
    if (_phase != HostPhase.arranging) return;
    _phase = HostPhase.lobby;
    _layout = null;
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  /// Builds the world from the calibration data and tells each phone where to
  /// sit. Play does not start until every phone confirms.
  void sendPlacement() {
    if (!canPlacePhones) return;

    final solved = const LayoutSolver().solve(
      [for (final p in _phones) CalibratedPhone(p.phoneId, p.metrics!)],
      arrangement: game.arrangement,
    );
    _layout = solved;
    _phase = HostPhase.placing;
    // The board is being laid out; the game is no longer joinable, so stop
    // advertising it as open.
    _updateBeacon();
    for (final p in _phones) {
      p.confirmed = false;
    }

    for (final phone in _phones) {
      final l = solved.forPhone(phone.phoneId)!;
      phone.link.send({
        'type': HostMsg.layout,
        ...l.toJson(),
        'coverage': solved.coverage.toJson(),
        ..._gameFields,
      });
    }
    _broadcastLobby();
    notifyListeners();
  }

  void _beginPlay() {
    final solved = _layout;
    if (solved == null) return;

    final sim = game.build(solved.coverage);
    _sim = sim;
    _phase = HostPhase.playing;
    _stepCount = 0;
    _accumulatorMs = 0;
    _lastClockUs = _clock.elapsedMicroseconds;

    _broadcast({
      'type': HostMsg.worldInit,
      'board': solved.coverage.board.toJson(),
      'entities': [for (final s in sim.specs) s.toJson()],
      ..._gameFields,
      // Whatever this particular game needs: a sling anchor, a target score.
      ...sim.worldInitExtras(),
    });
    _broadcast({'type': HostMsg.start});

    const period = Duration(microseconds: 1000000 ~/ GameConfig.simHz);
    _loop = Timer.periodic(period, (_) => _tick());
    notifyListeners();
  }

  /// Fixed-timestep loop. The timestep is fixed so the sim stays deterministic
  /// and snapshot timestamps land on exact multiples of the step — the client
  /// interpolator gets an evenly spaced timeline to walk along.
  void _tick() {
    final sim = _sim;
    if (sim == null) return;

    const stepMs = 1000 / GameConfig.simHz;
    final nowUs = _clock.elapsedMicroseconds;
    // Clamp so a stall (debugger, app backgrounded) can't trigger a
    // catch-up avalanche of steps.
    final deltaMs = ((nowUs - _lastClockUs) / 1000).clamp(0.0, 100.0);
    _lastClockUs = nowUs;
    _accumulatorMs += deltaMs;

    var stepped = false;
    while (_accumulatorMs >= stepMs) {
      sim.step(1 / GameConfig.simHz);
      _accumulatorMs -= stepMs;
      _stepCount++;
      stepped = true;
    }
    if (!stepped) return;

    final sling = sim.slingState();
    _broadcast({
      'type': HostMsg.state,
      'tick': sim.tick,
      't': simTimeMs,
      'entities': [for (final e in sim.entityStates()) e.toJson()],
      // Games without a slingshot leave the field out entirely rather than
      // sending a meaningless one.
      if (sling != null) 'sling': sling.toJson(),
      if (sim.progress != null) 'progress': sim.progress!.toJson(),
    });

    if (sim.won) _finishGame();
  }

  /// The round is over. Keep the final frame on screen — the tower mid-collapse
  /// is the reward — and tell everyone what is next.
  void _finishGame() {
    if (_phase != HostPhase.playing) return;
    _loop?.cancel();
    _loop = null;
    _phase = HostPhase.won;

    _broadcast({
      'type': HostMsg.won,
      'game': game.id,
      'gameTitle': game.title,
      'nextGame': nextGame.id,
      'nextTitle': nextGame.title,
      'nextTagline': nextGame.tagline,
      'nextArrangement': nextGame.arrangement.wireName,
      if (_sim?.progress != null) 'progress': _sim!.progress!.toJson(),
    });
    _broadcastLobby();
    notifyListeners();
  }

  /// On to the next game in the playlist, which means a new board shape and so
  /// a fresh trip through the arrangement and placement screens.
  void advanceToNextGame() {
    if (_phase != HostPhase.won) return;
    _gameIndex++;
    _sim = null;
    _layout = null;
    for (final p in _phones) {
      p.confirmed = false;
    }
    _phones.removeWhere((p) => !p.connected);
    _phase = HostPhase.arranging;
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  void resetBird() => _sim?.reset();

  /// Tear the world down and set the *same* game up again — the debug panel's
  /// "re-calibrate", for when a measurement was wrong.
  void recalibrate() {
    _loop?.cancel();
    _loop = null;
    _sim = null;
    _layout = null;
    _warning = null;
    _phones.removeWhere((p) => !p.connected);
    for (final p in _phones) {
      p.confirmed = false;
    }
    _phase = HostPhase.arranging;
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  /// All the way back to the connection screen, mid-session.
  void returnToLobby() {
    _loop?.cancel();
    _loop = null;
    _sim = null;
    _layout = null;
    _warning = null;
    _phones.removeWhere((p) => !p.connected);
    for (final p in _phones) {
      p.confirmed = false;
    }
    _phase = HostPhase.lobby;
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  void dismissWarning() {
    _warning = null;
    notifyListeners();
  }

  // ------------------------------------------------------------- broadcast

  void _broadcast(Map<String, dynamic> msg) {
    for (final p in _phones) {
      if (p.connected) p.link.send(msg);
    }
  }

  /// Which game is on, repeated on every message that could be a client's
  /// first sight of it. Cheap, and it means a client never has to remember a
  /// game id it was told about three screens ago.
  Map<String, dynamic> get _gameFields => {
    'game': game.id,
    'gameTitle': game.title,
    'gameTagline': game.tagline,
    'gameGoal': game.goal,
    'arrangement': game.arrangement.wireName,
  };

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

  @override
  void dispose() {
    _loop?.cancel();
    for (final t in _pending.values) {
      t.cancel();
    }
    _pending.clear();
    _beacon?.dispose();
    _beacon = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _transport.dispose();
    super.dispose();
  }
}
