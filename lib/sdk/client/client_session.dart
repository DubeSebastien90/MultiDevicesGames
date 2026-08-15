import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/audio_engine.dart';
import '../audio/audio_output.dart';
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
import '../render/player_art.dart';
import '../catalog.dart';
import '../contract/entity.dart';
import '../contract/game.dart';
import '../contract/sim.dart' show OutcomeKind, PhoneSlice;
import '../contract/view.dart';
import '../score/scoreboard.dart';
import 'interruption_watcher.dart';
import 'snapshot_buffer.dart';

enum ClientPhase {
  connecting,
  lobby,
  placing,
  playing,
  finished,

  /// The playlist is spent and the host has put the final standings up. The end
  /// of the evening's run, on every screen at once.
  scoreboard,

  /// Connected, but with no place in the round the table is playing — a phone
  /// that came back mid-game. It waits for the next one.
  waiting,
  rejected,
  disconnected,
}

/// What one phone is told about a round that ended.
class RoundVerdict {
  const RoundVerdict({
    required this.headline,
    required this.line,
    required this.celebrate,
  });

  /// 'You win!', 'You lost', 'A draw', 'Well played!', 'Round over'. The
  /// platform's words, so five phones never disagree about the phrasing of the
  /// same result.
  final String headline;

  /// The game's line for *this* phone, if it gave one.
  final String? line;

  /// Whether to show this as a win — the trophy rather than the neutral icon.
  final bool celebrate;
}

/// A round that ended, and what follows it.
///
/// [nextTitle] is null when the round was a one-off started from the games
/// list. Its absence is how every phone knows this ends at the lobby rather
/// than chaining into another game.
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

  /// What kind of ending this was, as the game declared it.
  final OutcomeKind kind;

  /// Who won, when [kind] is [OutcomeKind.contest].
  final Set<String>? winners;

  /// A line for one phone in particular, keyed by `phoneId`.
  final Map<String, String>? lines;

  /// What to put on [phoneId]'s screen.
  ///
  /// **The only place this is decided.** Every phone runs it, including the
  /// host's own, so the table cannot be shown two different verdicts for one
  /// round — the sort of split that has bitten this codebase every time one
  /// fact had two implementations.
  RoundVerdict verdictFor(String? phoneId) {
    final line = phoneId == null ? null : lines?[phoneId];

    switch (kind) {
      case OutcomeKind.contest:
        // No id means this phone has not been welcomed, so it is neither a
        // winner nor a loser. Telling it that it lost would be inventing a
        // result out of missing information.
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

  /// How to rearrange the phones for what is coming.
  final String? nextInstruction;

  /// This was the last game of a playlist run, so what comes after this screen
  /// is the final standings rather than the games list.
  ///
  /// Told rather than inferred: from a joiner, a spent playlist and a one-off
  /// game look identical — neither has a next game — and they end in different
  /// places.
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

/// One phone's view of the session: a viewport onto a world it does not own.
///
/// It sends raw local touches up and renders whatever the host describes. It
/// runs no simulation — which is exactly why every screen agrees.
class ClientSession extends ChangeNotifier {
  ClientSession({
    required Transport transport,
    required DeviceMetrics metrics,
    String? joinCode,
    String? deviceId,
    AudioOutput? audioOutput,
  }) : _transport = transport,
       _metrics = metrics,
       _joinCode = joinCode,
       _deviceId = deviceId,
       audio = AudioEngine(output: audioOutput);

  final Transport _transport;
  DeviceMetrics _metrics;

  /// The 5-digit code proving we were invited. Null on the host's own
  /// loopback, which the host trusts without asking.
  final String? _joinCode;

  /// What this device calls itself, the same on every run.
  ///
  /// Offered rather than claimed: the host hands a seat back only if it is
  /// empty, so this can never take one from a phone still sitting in it.
  final String? _deviceId;

  final buffer = SnapshotBuffer();
  final _clock = Stopwatch()..start();

  /// Watches for the screen being covered by something that is not the player
  /// leaving — the only trace NameDrop leaves that an app is allowed to see.
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

  /// Something the table should know: a player arriving or leaving while the
  /// board was being laid out, and what is being played now.
  /// Somebody arrived or left while the table was being set up.
  TableChange? get tableChange => _tableChange;
  ///
  /// Cleared by the host, through the lobby broadcast — there is deliberately no
  /// local dismiss. A joiner putting this away on its own would leave it looking
  /// like the table had moved on when it had not.
  TableChange? _tableChange;

  String? get warning => _warning;
  String? _warning;

  /// Stop showing it. Local — the host is not told, because the host said it.
  void dismissWarning() {
    _warning = null;
    notifyListeners();
  }

  /// How the phones should be arranged for this round.
  String? get instruction => _instruction;
  String? _instruction;

  /// Every screen's place on the board, in board order, as the game's
  /// `planBoard` decided it. What the placement diagram draws.
  List<PhoneSlice> get slices => _slices;
  List<PhoneSlice> _slices = const [];

  /// This phone's ear.
  ///
  /// One per device, the host's included — the host's own screen is a viewport
  /// like any other and its speaker is reached the same way, which is what
  /// keeps the sim from ever having to know it is running beside one.
  ///
  /// Silent unless a real [AudioOutput] was passed in. The app passes one; a
  /// test does not, and so a suite on a machine with no audio device stays
  /// quiet without anybody having to remember to mute it.
  final AudioEngine audio;

  /// Everyone in the round, assembled from the slices the host already sends.
  ///
  /// Colour crosses the wire on [PhoneSlice] and always has, so a roster costs
  /// nothing: no new message, no new field, no protocol version. This is only
  /// the assembly the games were each doing for themselves.
  Roster get roster => Roster(
    [
      for (final s in _slices)
        if (s.color != null)
          Player(phoneId: s.phoneId, color: s.color!, label: s.label),
    ],
    hostPhoneId: _hostPhoneId,
  );

  /// Whose phone is running the session, as the lobby broadcast said.
  String? _hostPhoneId;

  /// Whether this phone still owes the table the opening animation.
  ///
  /// True from the layout that starts a run until the curtain lifts. The board
  /// arrives underneath it and the view loads behind it, so the seconds are
  /// spent on something rather than waited out.
  bool get showIntro => _showIntro;
  bool _showIntro = false;

  /// The curtain is up. Local — nobody else is waiting on this phone.
  void introFinished() {
    if (!_showIntro) return;
    _showIntro = false;
    notifyListeners();
  }

  /// This phone's player: colour, character, art and voice.
  ///
  /// Null before the board is compiled — the roster is built from the slices,
  /// which arrive with the layout.
  Player? get me => _phoneId == null ? null : roster.byPhone(_phoneId!);

  /// The edge stripes for *this* phone — where its screen meets its neighbours.
  /// Match the colours up and the board is right.
  List<EdgeMarker> get myLinks => _myLinks;
  List<EdgeMarker> _myLinks = const [];

  /// Every screen's stripes, for the schema.
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
      // The code first: the host ignores every other message until it has one,
      // and answers `welcome` only once it matches.
      _transport.send({
        'type': ClientMsg.join,
        if (_joinCode != null) 'code': _joinCode,
        if (_deviceId != null) 'deviceId': _deviceId,
        'catalog': GameCatalog.fingerprint,
      });
      _sendCalibration();
      _pingTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _sendPing());
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

  /// This phone's colour, as the host last confirmed it.
  ///
  /// Read from the lobby broadcast rather than remembered locally, so a pick
  /// that lost a race to another phone corrects itself with no special case:
  /// the swatch simply never lights up.
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

  /// Colours already spoken for, including this phone's own.
  Set<String> get takenColorIds => {
    for (final p in _lobbyPhones)
      if (p['color'] is String) p['color'] as String,
  };

  /// Ask to be [color]. The host decides; watch [myColor] for the answer.
  void pickColor(PlayerColor color) {
    _transport.send({
      'type': ClientMsg.pickColor,
      'phoneId': _phoneId,
      'color': color.id,
    });
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

  /// Tell the host the screen was covered, and for how long.
  ///
  /// Reported on the way *out* of the interruption rather than into it, for
  /// the plain reason that its length is not known until it ends — and the
  /// length is half of what makes it worth reporting. The cost is that the two
  /// phones of a pair report at different moments, because two people dismiss
  /// a card at their own speed; sending how long ago it *began* is what lets
  /// the host line them back up.
  void _sendInterrupted(Duration held) {
    _transport.send({
      'type': ClientMsg.interrupted,
      'agoMs': held.inMilliseconds,
    });
  }

  /// 'I am in place.'
  ///
  /// Answered in this player's own voice, on this phone, immediately. It is
  /// local feedback for a local tap — there is no shared instant to agree with,
  /// and waiting eighty milliseconds to acknowledge a finger is the one thing
  /// local sound exists to avoid. It is also the first time most people hear
  /// which character they are.
  void confirmPlacement() {
    final player = me;
    if (player != null) audio.play(player.soundHappy);
    _transport.send({'type': ClientMsg.confirmPlacement, 'phoneId': _phoneId});
  }

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
    // The same instant the entities are sampled at, so a sound and the picture
    // that caused it arrive together rather than eighty milliseconds apart.
    audio.pump(buffer.renderTimeMs);
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
        _warning = msg['warning'] as String?;
        _tableChange = TableChange.fromJson(msg['tableChange']);
        _lobbyPhones = [
          for (final p in msg['phones'] as List) p as Map<String, dynamic>,
        ];
        _hostPhase = msg['phase'] as String?;
        _hostPhoneId = (msg['host'] as String?) ?? _hostPhoneId;
        _adoptGame(msg['game'] as String?);
        // The host went back to setting up: follow it out of whatever screen
        // this phone is on rather than stranding it on a stale one.
        //
        // Any screen, not only the results one. A phone left on the placement
        // screen for a round the host has abandoned is holding a diagram of a
        // board that no longer exists, waiting to be told where to stand by
        // nobody — which is what the dead end looked like from a joiner: the
        // host returned to the lobby and everybody else kept the old screen.
        //
        // `rejected` and `disconnected` are deliberately not in the set: those
        // are this phone's own state and the host does not get to talk it out
        // of them.
        const stale = {
          ClientPhase.placing,
          ClientPhase.playing,
          ClientPhase.finished,
          // Whatever it was waiting for is not happening, so it waits in the
          // lobby with everybody else.
          ClientPhase.waiting,
          // The run has been totalled up and put away.
          ClientPhase.scoreboard,
        };
        if (_hostPhase == 'lobby' && stale.contains(_phase)) {
          _phase = ClientPhase.lobby;
          _result = null;
        }

        // The run is over and the host has put the final standings up. Every
        // phone follows, from wherever it happened to be — the results screen
        // usually, the placement screen when the table ran out of games it could
        // play while it was still being laid out.
        //
        // `rejected` and `disconnected` stay out of it for the same reason they
        // stay out of the set above: those are this phone's own state, and the
        // host does not get to talk it out of them.
        const mine = {ClientPhase.rejected, ClientPhase.disconnected};
        if (_hostPhase == 'scoreboard' && !mine.contains(_phase)) {
          _phase = ClientPhase.scoreboard;
          _result = null;
        }
        notifyListeners();

      case HostMsg.sitOut:
        _phase = ClientPhase.waiting;
        // Nothing of the last round is theirs to show: no board, no verdict.
        _result = null;
        notifyListeners();

      case HostMsg.layout:
        _layout = PhoneLayout.fromJson(msg);
        _coverage =
            CoverageMap.fromJson(msg['coverage'] as Map<String, dynamic>);
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
        _myLinks =
            everyLink.where((l) => l.phoneId == _layout!.phoneId).toList();
        _adoptGame(msg['game'] as String?);
        _phase = ClientPhase.placing;
        _result = null;
        _descriptors.clear();
        buffer.clear();
        // Started, not awaited, during the one stretch of dead time there is:
        // people are pushing phones together. Only the colours at this table.
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
        // Forgotten at the same moment the host forgets it, rather than waiting
        // for a lobby broadcast that does not come until the round is over.
        _warning = null;
        _tableChange = null;
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
        _playVerdict(_result!);
        notifyListeners();

      case HostMsg.sound:
        // Queued, not played. It fires when this phone's delayed clock reaches
        // the instant the host stamped on it — see [AudioEngine].
        audio.receive(msg);

      case HostMsg.pong:
        final sent = (msg['t'] as num).toDouble();
        _rttMs = _clock.elapsedMilliseconds - sent;

      case HostMsg.nameDropSuspected:
        // Reopen the question, and say nothing about it now. A full-screen
        // notice about being interrupted, delivered as an interruption, would
        // be a strange thing to do to somebody mid-round — so this only
        // changes what the lobby will ask next time it is reached.
        //
        // Not awaited and not reported: whether the write lands is not worth
        // stalling a message pump over, and there is nothing on screen that
        // depends on it.
        NameDropPref.save(NameDropStatus.waiting);
    }
  }

  /// The round's verdict, in this player's own voice, on this phone.
  ///
  /// Decided locally rather than sent, because every phone already has the
  /// outcome and already works out its own headline from it — see
  /// [RoundResult.verdictFor]. Routing it through the host would be a second
  /// implementation of a question that must have exactly one answer, which is
  /// the mistake this codebase has made before.
  ///
  /// A draw is **silence**. Nobody won and nobody lost, and a sad voice on
  /// every phone would be telling eight people they lost a round that nothing
  /// lost — the same reason [OutcomeKind.draw] exists rather than being
  /// inferred from a missing winner.
  void _playVerdict(RoundResult result) {
    final player = me;
    if (player == null || result.kind == OutcomeKind.draw) return;
    final verdict = result.verdictFor(_phoneId);
    audio.play(verdict.celebrate ? player.soundHappy : player.soundSad);
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
    if (game == null || layout == null) return;

    // A build already running is not a reason to drop this request. Whatever
    // arrived is newer, and silently returning here left the phone with no view
    // and nothing to trigger another attempt.
    if (_viewLoading) {
      _viewWantedAgain = true;
      return;
    }
    if (_view != null) return;

    _viewLoading = true;
    try {
      final view = game.createView(
        ViewContext(
          phoneId: layout.phoneId,
          board: layout.board,
          // Built here rather than passed per frame: the roster is fixed for
          // the round, and the slices it comes from arrived with the layout
          // that triggered this build.
          roster: roster,
          audio: audio,
        ),
      );
      await view.load();

      // The round can have moved on while that was loading. Adopting this view
      // now would render the previous game's artwork over the current one.
      if (!identical(_game, game)) {
        view.dispose();
        return;
      }
      _view = view;
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

  /// A layout arrived while a view was still being built, so the build has to
  /// happen again once this one lets go.
  bool _viewWantedAgain = false;

  void _disposeView() {
    _view?.dispose();
    _view = null;
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    _interruptions.stop();
    _sub?.cancel();
    _disposeView();
    audio.dispose();
    _transport.dispose();
    super.dispose();
  }
}
