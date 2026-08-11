import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../platform_config.dart';
import '../model/device_identity.dart';
import '../model/device_metrics.dart';
import '../model/player_color.dart';
import '../net/discovery.dart';
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
  /// From the **Play** button: the whole list, once, then back to the lobby.
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
  /// never burns a phone number. Only meaningful inside this session.
  String phoneId = '';

  /// What the device on the other end calls itself, the same on every run.
  /// How a phone that drops out is recognised when it comes back.
  String? deviceId;

  final PeerLink link;

  /// False until the right code arrives. Everything this peer says before then
  /// is ignored.
  bool authenticated = false;

  DeviceMetrics? metrics;
  bool confirmed = false;
  bool connected = true;

  /// Assigned the moment this phone is admitted, changeable in the lobby.
  /// Unique across the session — the host is the only thing that can promise
  /// that, so the host is the only thing that writes it.
  PlayerColor? color;

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

  // JOIN CODE DISABLED — the lockout only means something with a code to get
  // wrong.
  //
  // /// A stranger gets this many wrong guesses before we stop answering them.
  // static const int _maxWrongGuesses = 5;
  // static const Duration _lockout = Duration(seconds: 30);

  static const Duration _joinDeadline = Duration(seconds: 15);

  final HostTransport _transport;
  final String _name;
  final String _joinCode;
  final bool _advertise;

  final _clock = Stopwatch();
  final _phones = <PhoneRecord>[];
  final _subs = <StreamSubscription<dynamic>>[];
  final _pending = <PhoneRecord, Timer>{};
  // JOIN CODE DISABLED
  // final _wrongGuesses = <String, int>{};
  // final _lockedOut = <String, DateTime>{};

  /// The session standings, shared by every game.
  final scores = Scoreboard();

  DiscoveryBroadcaster? _beacon;

  HostPhase _phase = HostPhase.idle;
  Uri? _address;
  GameSim? _sim;
  BoardLayout? _layout;
  Timer? _loop;
  String? _warning;

  /// Position in the playlist. Only ever goes up within a run, and resets when
  /// the table lands back in the lobby — the list is played through once.
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

  /// Everyone the session knows about, including phones that have dropped out.
  ///
  /// A player who disconnects stays on this list, marked not connected, so the
  /// standings keep one row per person rather than growing a second one when
  /// they come back.
  List<PhoneRecord> get phones => List.unmodifiable(_phones);

  /// The phones actually here — the ones a round is built from.
  ///
  /// Everything about *playing* counts these: how many are at the table, who
  /// gets a slice of the board, whether a game can start. Everything about
  /// *remembering* — the standings, and matching a returning phone to who it
  /// was — counts [phones].
  List<PhoneRecord> get _present =>
      [for (final p in _phones) if (p.connected) p];

  double get simTimeMs => _stepCount * (1000 / PlatformConfig.simHz);

  /// Set when a game's `planBoard` produced something unusable. The round never
  /// starts, and this says why on the host's own screen.
  String? get planError => _planError;
  String? _planError;

  /// The game the playlist would start right now, or null if none fits.
  MultiscreenGame? get upcoming =>
      GameCatalog.playableFrom(_gameIndex, _present.length);

  bool get canStart =>
      _phase == HostPhase.lobby &&
      _present.isNotEmpty &&
      _present.every((p) => p.calibrated) &&
      upcoming != null;

  /// Why the Play button is unavailable, for the lobby to say out loud.
  String? get blockedReason {
    if (_present.isEmpty) return 'Waiting for a phone to connect…';
    if (!_present.every((p) => p.calibrated)) {
      return 'Waiting for every phone to report its size…';
    }
    if (upcoming == null) {
      // Say what would help, not just what is wrong. A parity rule in
      // particular is baffling otherwise: four phones failing when three and
      // five both work needs explaining.
      final sizes = GameCatalog.playableTableSizes();
      final nearest = sizes.where((n) => n > _present.length).toList();
      final advice = nearest.isEmpty
          ? ''
          : ' Try ${nearest.first} phone(s).';
      return 'No game fits ${_present.length} phone(s).$advice '
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
    // A round in progress is no longer a closed door here.
    //
    // It used to be turned away the moment a socket opened, which was too
    // early to be fair: at that point the host knows nothing about who is
    // knocking. Somebody whose phone died two minutes ago is not a stranger,
    // and the seat they left is still on the roster with their score in it. So
    // the door is answered, and the decision waits for the `join` message,
    // where there is a name to judge — see [_handleJoin].

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

    // Still worth waiting on with the code gate open: the join message is also
    // what carries the app fingerprint, so a peer that never sends one has not
    // proved it can render this build.
    _pending[record] = Timer(_joinDeadline, () {
      if (_pending.remove(record) != null) {
        // JOIN CODE DISABLED — was 'No join code was sent.'
        _reject(link, 'That phone never finished joining.');
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

    // JOIN CODE DISABLED — anyone on this WiFi who finds the beacon is let in.
    // The code is still generated, still sent by clients and still in the QR;
    // it is simply not checked. To bring the door policy back, delete the
    // `_admit` below and uncomment the block under it, then the four other
    // `JOIN CODE DISABLED` markers (`grep -rn "JOIN CODE DISABLED"`).
    final deviceId = msg['deviceId'] as String?;

    // The door policy for a round already under way: your own seat, or nothing.
    //
    // A returning player is let back in because the table already knows them —
    // their seat is on the roster, their score is in it, and if the round was
    // laid out while they were here then a slice of the board is still theirs.
    // A phone nobody has met cannot be let in, and not out of strictness: the
    // board was compiled for the phones that were present, so there is no slice
    // to give them and no way to make one without asking everybody to pick
    // their phones up and start again.
    if (_phase != HostPhase.lobby && _seatFor(deviceId) == null) {
      _reject(
        record.link,
        'That game has already started. Ask the host to re-calibrate.',
      );
      return;
    }

    _admit(record, deviceId: deviceId);

    // final offered = (msg['code'] as String?)?.trim() ?? '';
    // if (_codeMatches(offered)) {
    //   _wrongGuesses.remove(record.link.debugName);
    //   _admit(record);
    //   return;
    // }
    //
    // final remote = record.link.debugName;
    // final wrong = (_wrongGuesses[remote] ?? 0) + 1;
    // _wrongGuesses[remote] = wrong;
    // if (wrong >= _maxWrongGuesses) {
    //   _lockedOut[remote] = DateTime.now().add(_lockout);
    //   _wrongGuesses.remove(remote);
    // }
    // _reject(record.link, 'Wrong code.');
  }

  // JOIN CODE DISABLED — unused while the gate is open, so it is commented out
  // rather than left to trip the analyzer.
  //
  // /// Constant-time-ish compare. The timing of a 5-digit string comparison is
  // /// not a realistic attack over WiFi, but there is no reason to leak it.
  // bool _codeMatches(String offered) {
  //   if (offered.length != _joinCode.length) return false;
  //   var diff = 0;
  //   for (var i = 0; i < offered.length; i++) {
  //     diff |= offered.codeUnitAt(i) ^ _joinCode.codeUnitAt(i);
  //   }
  //   return diff == 0;
  // }

  /// The seat this device left behind, if it is empty and waiting.
  ///
  /// Matched on the device's own name rather than the phone number this session
  /// handed out. That number is short, guessable and reused, so a seat could be
  /// claimed by typing it; a device id is picked at random once and published
  /// to nobody. It also outlives the app being closed, which the number never
  /// could — it only ever existed in memory.
  ///
  /// Only a seat whose phone has actually gone: a live connection claiming a
  /// seat in use is either a mistake or somebody helping themselves to a
  /// stranger's score, and either way the answer is to treat them as a
  /// newcomer rather than to evict whoever is sitting there.
  PhoneRecord? _seatFor(String? deviceId) {
    if (deviceId == null || deviceId.isEmpty) return null;
    for (final p in _phones) {
      if (p.deviceId == deviceId && !p.connected) return p;
    }
    return null;
  }

  void _admit(PhoneRecord record, {String? deviceId}) {
    record.authenticated = true;
    record.deviceId = deviceId;

    final returning = _seatFor(deviceId);
    if (returning != null) {
      // The same person, back again. They take their old seat with everything
      // that was in it — number, colour, measurements — so the scoreboard,
      // which is keyed by that number, carries straight on rather than opening
      // a second row under the same name.
      record.phoneId = returning.phoneId;
      record.color = returning.color;
      record.metrics ??= returning.metrics;
      _phones[_phones.indexOf(returning)] = record;
    } else {
      record.phoneId = 'p${_nextPhoneNumber++}';
      // Seat them immediately. A player who never opens the picker still has an
      // identity, so choosing is a change rather than a gate on starting.
      record.color = PlayerPalette.firstFree(_takenColorIds());
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

    // Back before the round began: they belong on the board, so it is laid out
    // again to include them. Everybody confirms afresh — one more phone changes
    // where all the others go.
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

  /// Bring one phone up to date with a round that is already happening.
  ///
  /// Everything a phone is told when a round starts, said again to one peer:
  /// where its screen sits, what is in the world, and that play is under way.
  /// Sent only if the board still holds a slice for it — a phone that dropped
  /// out *before* the round was laid out has no place in it, so it waits in the
  /// lobby for the next one rather than being handed an empty screen.
  ///
  /// The entity list is taken from the simulation as it stands rather than from
  /// how the round began, so what arrives is the world as it is now; the
  /// ordinary snapshots that follow carry it on from there.
  void _catchUp(PhoneRecord record) {
    final solved = _layout;
    if (solved == null || _phase == HostPhase.lobby) return;

    final mine = solved.forPhone(record.phoneId);
    if (mine == null) return;

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
    // Long enough for the frame to make it out before the socket shuts.
    Future<void>.delayed(const Duration(milliseconds: 300), link.close);
  }

  Iterable<String> _takenColorIds() sync* {
    for (final p in _phones) {
      final c = p.color;
      if (c != null) yield c.id;
    }
  }

  /// First come, first served, decided here because only here can decide it.
  ///
  /// Two phones tapping Green in the same instant both send a request; the one
  /// whose packet arrives second is simply told no, by receiving a lobby
  /// snapshot in which Green belongs to somebody else. No error message and no
  /// special case on the client — the broadcast is already the source of truth
  /// about who is what colour, so losing the race just looks like the swatch
  /// not taking.
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

  void _updateBeacon() => _beacon?.update(
    players: _phones.where((p) => p.connected).length,
    open: _phase == HostPhase.lobby,
    // Which seats are sitting empty, said in a way only their owner
    // recognises. It is what lets a phone see that a game already under way is
    // still *its* game, instead of tapping and being turned away.
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

    // Kept either way, marked not connected.
    //
    // The lobby used to erase them, which is why somebody who dropped and came
    // back appeared twice in the standings: they were admitted as a stranger
    // and handed a fresh phone number, and the scoreboard is keyed by that
    // number. Remembering the seat is what lets them have it back.
    if (_phase != HostPhase.lobby) {
      // Mid-game: leave the world alone (its slice just goes dark) rather than
      // silently rearranging a board people have physically laid out.
      _warning = '${record.label} disconnected — re-calibrate to rebuild the '
          'board.';
      if (_phase == HostPhase.placing) {
        _layoutAgainWithoutThem(record);
      } else {
        _tellTheGameSomebodyLeft(record);
      }
    }
    _broadcastLobby();
    // Their row stays on every screen, name and score intact, rather than the
    // rest of the table being left with whatever it happened to know last.
    _broadcastScores();
    _updateBeacon();
    notifyListeners();
  }

  /// Somebody walked off while the table was still being laid out.
  ///
  /// The arrangement was compiled for the phones that were here, so their
  /// leaving leaves a hole in the middle of it: a slice of the world belonging
  /// to a screen nobody is holding. Starting anyway would hand everyone else a
  /// board with a gap in it.
  ///
  /// So it is worked out again for whoever is left, and everybody is asked to
  /// confirm afresh — not out of pedantry, but because the new arrangement
  /// almost certainly puts their phone somewhere else, and a Ready from before
  /// was about a table that no longer exists.
  ///
  /// Only when the phone that left was actually *on* the board. One that
  /// rejoined without a slice and dropped out again changes nothing about the
  /// arrangement, and rebuilding would make everybody re-place their phones for
  /// no reason.
  void _layoutAgainWithoutThem(PhoneRecord who) {
    if (_layout?.forPhone(who.phoneId) == null) {
      // They were never on this board — but they may have been the last one
      // everybody was waiting on.
      _beginPlayIfEveryoneIsInPlace();
      return;
    }

    _layOutAgain(because: '${who.label} left');
  }

  /// Lay the table out again for exactly the phones that are here.
  ///
  /// Used whenever the table changes shape while it is still being set up —
  /// somebody walking off, or walking back on. Both need the same thing: an
  /// arrangement for the phones actually present, and everybody asked to
  /// confirm afresh, because the new one almost certainly puts their phone
  /// somewhere else.
  ///
  /// If the game cannot be played by who is left, the playlist moves on to one
  /// that can rather than dropping everybody back to the lobby — the table came
  /// here to play, and losing a player is a reason to change game, not to stop.
  ///
  /// Whether it can is asked of the *manifest*, not left to the layout to
  /// refuse, because most layouts will not: `Layouts.column` will happily
  /// arrange a single phone, so Ball Bin would have quietly gone ahead as a
  /// one-player game after its second player walked off.
  void _layOutAgain({required String because}) {
    final game = _game;
    // Forward only. The playlist is played through once, so a table that has
    // shrunk past what this game needs carries on down the list rather than
    // doubling back — and if nothing further suits it, the lobby is the honest
    // answer rather than replaying something.
    final index = game != null && game.manifest.fits(_present.length)
        ? _gameIndex
        : GameCatalog.playableIndexFrom(_gameIndex + 1, _present.length);

    if (index == null) {
      _planError = '$because — nothing left in the playlist fits '
          '${_present.length} phone(s). ${GameCatalog.requirementSummary()}.';
      _game = null;
      _layout = null;
      _phase = HostPhase.lobby;
      _broadcastLobby();
      notifyListeners();
      return;
    }

    // Said every time the table changes shape, not only when the game does.
    // Everybody is about to be asked to put their phone somewhere new and the
    // Ready they already gave has been thrown away; being told only when the
    // *game* changed would leave that looking like the app forgetting itself.
    _warning = '$because — next game: '
        '${GameCatalog.playlist[index].manifest.title}.';
    _startGame(index);
  }

  /// Start the round once everyone the board was built for says they are in
  /// place.
  ///
  /// **Everyone it was built for**, not everyone connected, and the difference
  /// is a phone that rejoined after the board was laid out. There is no slice
  /// for it — the arrangement was compiled for the phones that were here — so
  /// it never sees a placement screen and has nothing to confirm. Counting it
  /// left the table waiting for a fourth pair of hands that had no button to
  /// press.
  ///
  /// Also checked when somebody drops out, not only when somebody confirms:
  /// the last phone the round is waiting on might leave rather than press, and
  /// then no message ever arrives to ask the question again.
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

  /// Hand a mid-round disconnection to the game, or end the round if it has
  /// not asked to hear about them.
  ///
  /// The default is a draw rather than carrying on, because carrying on is a
  /// claim only the game can make. A hippo down one player is still a game; a
  /// two-player race with one runner is not, and finishing it would hand
  /// somebody a win they did not earn against somebody whose battery died.
  /// Ending level is the answer that is wrong in the fewest ways, and any game
  /// that disagrees says so by implementing [PlayerPresence].
  void _tellTheGameSomebodyLeft(PhoneRecord record) {
    final sim = _sim;
    if (sim == null || _phase != HostPhase.playing) return;

    if (sim is PlayerPresence) {
      (sim as PlayerPresence).onPlayerLeft(record.phoneId);
      return;
    }
    _finishRound(GameOutcome.draw(
      summary: '${record.label} dropped out',
    ));
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
        // This is where a phone stops being 'p2' and becomes a name: the label
        // rides in with the measurements. The standings are keyed by phone but
        // *read* by name, so they have to be told — without this, every other
        // phone at the table showed a nameless row for somebody it had already
        // met. The broadcast is diffed, so saying so costs nothing when nothing
        // has changed.
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
      : GameCatalog.playableFrom(_gameIndex + 1, _present.length);

  /// One game, then back to the lobby. The games list.
  ///
  /// Everything between the tap and the placement screen happens here, with no
  /// screen in between: the game already knows where the phones go.
  void startGame(MultiscreenGame game) {
    if (!canStart) return;
    if (!game.manifest.fits(_present.length)) return;
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
    // Always from the top: a run is the whole list, not a resumption of one
    // somebody abandoned.
    _startGame(GameCatalog.playableIndexFrom(0, _present.length)!);
  }

  /// Every game, with whether this table can play it. The lobby's list.
  List<GameOffer> get offers => [
    for (final game in GameCatalog.playlist)
      GameOffer(
        game: game,
        playable: canStart && game.manifest.fits(_present.length),
        reason: game.manifest.fits(_present.length)
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
      for (final p in _present)
        PhoneSpec.fromMetrics(p.phoneId, p.metrics!, color: p.color),
    ]);

    final BoardLayout solved;
    final BoardPlan plan;
    try {
      final rawPlan = game.planBoard(lobby);
      plan = NameDropOptimizer.optimize(rawPlan, lobby);
      solved = const BoardCompiler().compile(plan, lobby);
    } on BoardPlanError catch (e) {
      // The game's plan is unusable. Nobody is asked to rearrange a table for
      // a round that cannot run.
      //
      // Back to the lobby rather than wherever we were: this can now be reached
      // *from* the placement screen, when the table shrinks below what the game
      // needs, and leaving the phase alone would strand everybody on a screen
      // for a round that no longer has a board.
      _planError = '${game.manifest.title}: ${e.message}';
      _game = null;
      _layout = null;
      _phase = HostPhase.lobby;
      _broadcastLobby();
      notifyListeners();
      return;
    }

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

    // A game whose sim will not build is reported, not left hanging.
    //
    // `planBoard` is guarded where it runs, but a game can also refuse at
    // `createSim` — it is the first place a game sees the *compiled* board,
    // and the first place it can discover the table is not one it can play on.
    // Without this the exception escapes mid-transition, the phase never
    // advances, and every phone sits on the placement screen forever with
    // nothing on any screen to say why.
    final GameSim sim;
    try {
      sim = game.createSim(solved.contextFor(scores));
    } catch (e) {
      _planError = '${game.manifest.title}: $e';
      _phase = HostPhase.lobby;
      _game = null;
      _layout = null;
      _broadcastLobby();
      notifyListeners();
      return;
    }
    _sim = sim;

    // The notice has been read by now, so it stops here rather than following
    // the table into the next round. It is only ever shown on the placement
    // screen and in the lobby, and both are behind us — leaving it set means the
    // *next* time the board is laid out, whoever put it away sees it come back,
    // and whoever did not is reading last round's news.
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
  /// A game naming phones that are not at the table has almost certainly used
  /// its own indices — `'0'`, `'blue'` — where a `phoneId` was wanted, and the
  /// symptom is every player being told they lost. Said out loud at the moment
  /// it happens rather than left to be puzzled over on five screens at once.
  void _warnAboutUnknownPhones(GameOutcome outcome) {
    final known = {for (final p in _present) p.phoneId};
    final named = <String>{
      ...?outcome.winners,
      ...?outcome.lines?.keys,
    };
    final strangers = named.difference(known);
    if (strangers.isEmpty) return;

    _warning = '${_game?.manifest.title ?? 'That game'} ended naming phones '
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
    // Deliberately not dropped: a phone that has gone quiet keeps its place on
    // the roster, so its score is still there when it comes back.
    final index =
        GameCatalog.playableIndexFrom(_gameIndex + 1, _present.length);
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
    // Deliberately not dropped: a phone that has gone quiet keeps its place on
    // the roster, so its score is still there when it comes back.
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
    // Deliberately not dropped: a phone that has gone quiet keeps its place on
    // the roster, so its score is still there when it comes back.
    for (final p in _phones) {
      p.confirmed = false;
    }
    _phase = HostPhase.lobby;
    _mode = RoundMode.playlist;
    // Back to the top of the list. The playlist is played through once, so
    // without this a second Play would start from wherever the last one
    // stopped — and after a full run, from past the end, which reads as "no
    // game fits this table".
    _gameIndex = 0;
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
      // The table changing shape is news for every phone, not only the one
      // running the session — everybody is about to be asked to move.
      if (_warning != null) 'warning': _warning,
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
