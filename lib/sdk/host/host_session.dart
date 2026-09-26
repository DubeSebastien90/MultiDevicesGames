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

/// The host's journey through one session.
///
/// [lobby] is about *connecting* — the code, the QR, who is in, and everyone's
/// measurements. [placing] is about the table. There is deliberately no step in
/// between: the game's `planBoard` already decided the arrangement, better than
/// a host squinting at a diagram could.
///
/// [scoreboard] is the end of a run: the playlist is spent, the final standings
/// are on every screen, and the only way on is back to the lobby.
enum HostPhase { idle, lobby, placing, playing, finished, scoreboard }

/// How a round was started, which decides where it ends.
enum RoundMode {
  /// From the **Play** button: the whole list, once, then back to the lobby.
  playlist,

  /// From the games list: play that one, then back to the lobby.
  oneOff,
}

/// One entry in the host's list of games.
///
/// The eligibility check is answered once, here, rather than being re-derived
/// by whatever draws the list — so the reason a game is greyed out and the
/// reason it cannot be started are guaranteed to be the same reason.
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

  /// Whether the phones at the table right now could play it.
  ///
  /// Nothing to do with whether it has been ticked: the two are separate
  /// questions and the list shows both at once. A game that does not fit is
  /// greyed, ticked or not, because that is a fact about the table rather than
  /// a choice anybody made.
  final bool fitsTable;

  /// Why not, when it does not fit the phone count: 'needs 3+ phones'. Null
  /// when the game itself is fine and only the lobby is not ready.
  final String? reason;

  /// Whether the host has left it in the run.
  final bool chosen;

  /// A Premium game this host has not unlocked. Shown greyed with a lock
  /// rather than a checkbox — tapping it opens the paywall instead of ticking
  /// it, so there is no tick state to get out of sync with a purchase that
  /// has not happened yet.
  ///
  /// False while [lockPending]: "we have not heard back" is not "you have not
  /// paid", and only one of those may draw a padlock.
  final bool isLocked;

  /// A Premium game whose status is still being fetched.
  ///
  /// The third state, and the reason this is not one boolean. Until RevenueCat
  /// answers, a host who paid last week and a host who never paid are
  /// indistinguishable from inside the app — and of the two ways to guess, one
  /// is much worse than the other. Guessing *unlocked* offers a tick that may be
  /// taken away half a second later. Guessing *locked* puts a padlock and a
  /// PREMIUM badge on games somebody has already bought, which is the app
  /// calling a paying customer a freeloader while their phone looks for signal.
  ///
  /// So it guesses neither. A pending row is inert and says nothing about
  /// money, and it settles into [isLocked] or into an ordinary tickable row
  /// once there is an answer.
  final bool lockPending;

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
    PremiumStatus? premium,
    Random? random,
  }) : _transport = transport ?? WebSocketHostTransport(),
       _name = name,
       _joinCode = joinCode ?? generateJoinCode(),
       _advertise = advertise,
       _premium = premium,
       _random = random ?? Random();

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

  /// Deals the running order at **Play**. Injectable so a test can seed it and
  /// know which game comes up first.
  final Random _random;

  /// Null in tests and anywhere else Premium is not wired up — treated the
  /// same as "not premium", never as "everything unlocked". A missing gate
  /// must fail closed, not open.
  final PremiumStatus? _premium;

  /// Whether this host currently has Premium unlocked.
  bool get isPremiumUnlocked => _premium?.isPremium ?? false;

  /// Whether [isPremiumUnlocked] is an answer yet, or still a default.
  ///
  /// Only the *display* may consult this. Everything that decides what actually
  /// runs — [_skipping], [_mayStart] — must keep treating unsettled as "not
  /// premium", because failing closed is the whole reason a missing gate is
  /// safe. This exists so a screen can decline to say anything rather than say
  /// the wrong thing while waiting.
  ///
  /// A null [_premium] reads as settled: no paywall is wired up, that is not
  /// going to change, and a UI that waited on it would wait forever.
  bool get isPremiumSettled => _premium?.isReady ?? true;

  /// Why the Premium state could not be established, if it could not.
  ///
  /// Non-null means the padlocks on screen may be lying — the host might well
  /// have paid and this device simply could not find out. The games sheet says
  /// so out loud and offers a retry, because the alternative is a paying
  /// customer looking at a locked catalogue with no explanation and concluding
  /// the purchase failed.
  String? get premiumError => _premium?.error;

  final _clock = Stopwatch();
  final _phones = <PhoneRecord>[];
  final _subs = <StreamSubscription<dynamic>>[];
  final _pending = <PhoneRecord, Timer>{};
  // JOIN CODE DISABLED
  // final _wrongGuesses = <String, int>{};
  // final _lockedOut = <String, DateTime>{};

  /// The session standings, shared by every game.
  final scores = Scoreboard();

  GameAdvertiser? _beacon;
  bool _disposed = false;

  HostPhase _phase = HostPhase.idle;
  Uri? _address;
  GameSim? _sim;
  BoardLayout? _layout;
  Timer? _loop;
  String? _warning;

  /// Whether the next board laid out is the one at the start of a run.
  ///
  /// Set by the **Play** button and spent on the next layout broadcast, so the
  /// curtain falls once — between the lobby and the first game — and not again
  /// between the first game and the second. A re-calibrate re-lays the same
  /// board and does not raise it again, because the flag is already spent.
  bool _introPending = false;

  /// The round's audio queue. Made with the sim and thrown away with it, which
  /// is what makes handles round-scoped without anything having to expire them.
  RoundAudio? _audio;

  /// Position in [_order]. Only ever goes up within a run, and resets when
  /// the table lands back in the lobby — the list is played through once.
  int _gameIndex = 0;

  /// The order this run walks the catalogue in.
  ///
  /// Shuffled at **Play**, so no two evenings open with the same game, and put
  /// back to catalogue order in the lobby. Only the order is dealt: what gets
  /// skipped is still asked of [_skipping] and the table size on every step, so
  /// a shuffled run steps over an unticked, locked or too-big game exactly as
  /// an ordered one does.
  List<MultiscreenGame> _order = GameCatalog.playlist;

  /// Games the host has unticked, by id.
  ///
  /// The *exclusions* rather than the selection, so that everything is in the
  /// run until somebody says otherwise — including a game added in a later
  /// build, which a stored list of chosen ids would have quietly left out of
  /// every session that had ever been configured.
  final _skipped = <String>{};

  /// The games this run is playing, by id — fixed the moment **Play** was
  /// pressed. Null between runs.
  ///
  /// A run is decided once, from what was ticked *and* what the table could
  /// play at the time, and then it never grows. Asking the question again as
  /// the evening went on let a game the host had watched sit greyed out play
  /// itself the moment somebody's phone died: Flood needs two, so a table of
  /// three that ticked it saw it greyed, pressed Play, lost a phone — and got
  /// Flood, which the lobby had just finished promising was not in the run.
  ///
  /// Shrinking is still allowed and still happens, through the ordinary `fits`
  /// check on every step: a run can lose a phone and skip the games that needed
  /// it. Growing is the only thing this forbids.
  Set<String>? _runGames;

  /// What the walk leaves out right now.
  ///
  /// Everything outside the run once one is under way; the unticked games
  /// before that, which is what the lobby is choosing between. Either way,
  /// every Premium game is folded in on top when this host has not unlocked
  /// Premium — the one place that guarantee lives, so every query answered
  /// from [_skipping] (`runningOrder`, `upcoming`, `canStart`,
  /// `playableFrom`) automatically respects the paywall without having to
  /// remember to check it themselves.
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

  /// Somebody arrived or left while the table was being set up. See
  /// [TableChange] for why this is not a `warning`.
  TableChange? get tableChange => _tableChange;
  TableChange? _tableChange;

  /// The host has read it on everybody's behalf.
  ///
  /// Broadcast rather than local, unlike [dismissWarning]. Six phones each
  /// needing their own tap is six chances for one of them to be face-down on the
  /// table while the other five wait, and the message is about the table, not
  /// about any one player — so one person clears it for the room, the same
  /// person who chose the game.
  void dismissTableChange() {
    _tableChange = null;
    _broadcastLobby();
    notifyListeners();
  }

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
  List<PhoneRecord> get _present => [
    for (final p in _phones)
      if (p.connected) p,
  ];

  double get simTimeMs => _stepCount * (1000 / PlatformConfig.simHz);

  /// Set when a game's `planBoard` produced something unusable. The round never
  /// starts, and this says why on the host's own screen.
  String? get planError => _planError;
  String? _planError;

  /// Pairs of phones whose tops are still together in the current layout.
  /// Empty whenever [_layout] is null, which is what stops a stale set from
  /// being consulted in the lobby.
  Set<(String, String)> _dangerPairs = const {};

  final _nameDrop = NameDropDetector();

  /// The game the playlist would start right now, or null if none fits.
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

  /// Why the Play button is unavailable, for the lobby to say out loud.
  String? get blockedReason {
    if (_present.isEmpty) return 'Waiting for a phone to connect…';
    if (!_present.every((p) => p.calibrated)) {
      return 'Waiting for every phone to report its size…';
    }
    if (chosenGames.isEmpty) {
      // A different problem from "nothing fits", and it has a different fix:
      // this table is not too small, it has simply been emptied of games.
      return 'No games are ticked. Tap the gear to choose some.';
    }
    if (upcoming == null) {
      // Say what would help, not just what is wrong. A parity rule in
      // particular is baffling otherwise: four phones failing when three and
      // five both work needs explaining.
      //
      // Everything here is asked of the *ticked* games only. Advising a table
      // of two to find a third phone for a game they took out of the run would
      // be sending them after something they already said no to.
      final sizes = GameCatalog.playableTableSizes(skipping: _skipping);
      final nearest = sizes.where((n) => n > _present.length).toList();
      final advice = nearest.isEmpty ? '' : ' Try ${nearest.first} phone(s).';
      return 'No ticked game fits ${_present.length} phone(s).$advice '
          '${GameCatalog.requirementSummary(skipping: _skipping)}.';
    }
    return null;
  }

  // --------------------------------------------------------- the tick list

  /// The games the host has left ticked, in playlist order.
  ///
  /// Everything, until somebody unticks something: a table that never opens the
  /// list plays the whole catalogue, which is what it did before there was a
  /// list to open.
  ///
  /// A tick is a preference about the evening, not a claim about this minute —
  /// see [runningOrder] for what would actually be played.
  List<MultiscreenGame> get chosenGames => [
    for (final game in GameCatalog.playlist)
      if (!_skipped.contains(game.manifest.id)) game,
  ];

  /// What **Play** would play, in order, if it started now — and, once a run is
  /// under way, what it is still going to play.
  ///
  /// Ticked *and* a size this table can be. The two are separate facts and the
  /// list shows both, but only one of them is the run: a greyed game is not in
  /// it, however it is ticked, and nothing on screen should say otherwise. That
  /// is the whole reason this is not just [chosenGames].
  List<MultiscreenGame> get runningOrder {
    final skipping = _skipping;
    return [
      for (final game in GameCatalog.playlist)
        if (!skipping.contains(game.manifest.id) &&
            game.manifest.fits(_present.length))
          game,
    ];
  }

  /// Every game, with whether this table can play it and whether it is in the
  /// run. The host's game list.
  List<GameOffer> get offers => [
    for (final game in GameCatalog.playlist)
      GameOffer(
        game: game,
        fitsTable: game.manifest.fits(_present.length),
        reason: game.manifest.fits(_present.length)
            ? null
            : game.manifest.requirement(),
        // A locked game reads as un-chosen no matter what the tick list
        // remembers — "All" tickets it internally so a later purchase can
        // restore it without a special case, but the checkbox has to show
        // what Play is actually about to do, not what is stored.
        chosen: !_skipping.contains(game.manifest.id),
        // Locked only once we know. Until then the row is pending, which draws
        // no padlock and offers no tick — see [GameOffer.lockPending].
        isLocked: game.manifest.isPremium &&
            !isPremiumUnlocked &&
            isPremiumSettled,
        lockPending: game.manifest.isPremium &&
            !isPremiumUnlocked &&
            !isPremiumSettled,
      ),
  ];

  /// Tick or untick one game.
  ///
  /// Takes effect from the next game the run reaches rather than the current
  /// one, because the run walks the list by asking what comes next — so a game
  /// unticked mid-round is simply never arrived at.
  ///
  /// Choosing tonight's exact lineup is itself Premium. Without it, the host
  /// gets the default free run and every attempt to customize is ignored here,
  /// even if a caller forgets to route the tap through the paywall first.
  void chooseGame(MultiscreenGame game, {required bool chosen}) {
    if (!isPremiumUnlocked) return;
    final changed = chosen
        ? _skipped.remove(game.manifest.id)
        : _skipped.add(game.manifest.id);
    if (changed) notifyListeners();
  }

  /// Put the whole catalogue back in the run.
  void chooseAllGames() {
    if (!isPremiumUnlocked) return;
    if (_skipped.isEmpty) return;
    _skipped.clear();
    notifyListeners();
  }

  /// Take everything out, so one tick is enough to play exactly one game.
  ///
  /// Leaves the table unable to start, deliberately and visibly — [blockedReason]
  /// says so — rather than refusing the tap and leaving somebody wondering which
  /// of the twelve boxes is the one that will not come off.
  void chooseNoGames() {
    if (!isPremiumUnlocked) return;
    if (_skipped.length == GameCatalog.playlist.length) return;
    _skipped
      ..clear()
      ..addAll([for (final g in GameCatalog.playlist) g.manifest.id]);
    notifyListeners();
  }

  // ------------------------------------------------------------ lifecycle

  Future<Uri> start() async {
    _clock.start();
    final uri = await _transport.start();
    // Left before the socket was even up. Nothing below should outlive that —
    // above all not a beacon, which nobody would be left to stop.
    if (_disposed) return uri;
    _address = uri;
    _phase = HostPhase.lobby;
    _subs.add(_transport.onPeer.listen(_attachPeer));

    if (_advertise) {
      // Held before it is started, not after: [dispose] can land during the
      // start — leaving a lobby a moment after creating it — and it can only
      // stop a beacon it can see. Each advertiser copes with being disposed
      // mid-start; this is what makes sure it is told.
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

  /// Adds the host's own screen as a peer. Trusted: this peer is a function
  /// call away, not a socket, so there is nobody to prove anything to.
  /// The host's own phone, attached over loopback.
  ///
  /// Remembered because it is the table's speaker: a general sound plays here
  /// and nowhere else. Working it out from the roster instead — "the first
  /// seat" — would be wrong the first time the host's own phone reconnects and
  /// takes a different one.
  PhoneRecord? _localRecord;

  /// Which phone is the host's, or null when nothing is attached locally — a
  /// headless host in a test has no speaker, and general sounds go nowhere.
  String? get hostPhoneId => _localRecord?.phoneId;

  /// [preferredColor] is the host's own phone's usual colour — the same
  /// preference a joiner carries in its `join` message, which the trusted
  /// loopback never has to send.
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

    // Still worth waiting on with the code gate open: the join message is also
    // what carries the app fingerprint, so a peer that never sends one has not
    // proved it can render this build.
    _pending[record] = Timer(_joinDeadline, () {
      if (_pending.remove(record) != null) {
        // JOIN CODE DISABLED — was 'No join code was sent.'
        _reject(link, 'That phone never finished joining.');
      }
    });
    return record;
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
    if (!_openToStrangers && _seatFor(deviceId) == null) {
      _reject(
        record.link,
        'That game has already started. Ask the host to re-calibrate.',
      );
      return;
    }

    // Eight characters, eight people. A ninth phone would be let in with no
    // colour — invisible in the picker, unable to take one, and handed to a
    // game as a slice with nobody on it — so the door is shut instead. A seat
    // that still holds its colour (somebody coming back mid-round) is theirs
    // whatever the palette says.
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

  void _admit(
    PhoneRecord record, {
    String? deviceId,
    PlayerColor? preferredColor,
  }) {
    record.authenticated = true;
    record.deviceId = deviceId;

    final returning = _seatFor(deviceId);
    if (returning != null) {
      // The same person, back again. They take their old seat with everything
      // that was in it — number, colour, measurements — so the scoreboard,
      // which is keyed by that number, carries straight on rather than opening
      // a second row under the same name.
      record.phoneId = returning.phoneId;
      // Still theirs if they left mid-round, when the game was built around
      // it. Left in the lobby it was handed back to the palette, so they are
      // seated again like anybody arriving.
      record.color = returning.color ?? _seatColour(preferredColor);
      record.metrics ??= returning.metrics;
      _phones[_phones.indexOf(returning)] = record;
    } else {
      record.phoneId = 'p${_nextPhoneNumber++}';
      // Seat them immediately. A player who never opens the picker still has an
      // identity, so choosing is a change rather than a gate on starting.
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

    // No slice for them in the arrangement on the table, or a round that is
    // already over: either way there is nothing to catch up *to*, and they are
    // told so rather than left looking at a lobby while everyone else plays.
    //
    // The first case is a phone that was not part of this round — it dropped out
    // during placement, so the board was laid out again without it. The second
    // is somebody arriving at the results screen, who has missed the round
    // whether or not a slice still has their name on it.
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
    // Long enough for the frame to make it out before the socket shuts.
    Future<void>.delayed(const Duration(milliseconds: 300), link.close);
  }

  /// The colour a phone sits down in: the one it asked for if nobody has it,
  /// otherwise the first one free.
  ///
  /// The preference belongs to the phone, not to this session — it is what
  /// that person picked last time, anywhere — so the host remembers nothing
  /// and simply honours it when it can.
  PlayerColor? _seatColour(PlayerColor? preferred) {
    final taken = _takenColorIds().toSet();
    if (preferred != null && !taken.contains(preferred.id)) return preferred;
    return PlayerPalette.firstFree(taken);
  }

  /// Give the colours of everybody who is not here back to the palette.
  ///
  /// Only ever between rounds. Mid-round a colour *is* the player to the game —
  /// the roster, the board, whose goal is whose — so an absent player keeps it
  /// until the table is back somewhere nothing is built on it. They keep their
  /// seat and their score either way; what they lose is the right to stop
  /// somebody else being red. The standings draw them in grey meanwhile.
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

  /// Whether somebody the table has never met can walk in right now.
  ///
  /// The scoreboard counts as open. It is the lobby with the final standings on
  /// it — nothing is being played, no board has been laid out — so a person
  /// arriving between two runs belongs in the room for the next one rather than
  /// being told a game has already started.
  bool get _openToStrangers =>
      _phase == HostPhase.lobby || _phase == HostPhase.scoreboard;

  void _updateBeacon() => _beacon?.update(
    players: _phones.where((p) => p.connected).length,
    open: _openToStrangers,
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
    if (_openToStrangers) _releaseAwayColours();

    // Kept either way, marked not connected.
    //
    // The lobby used to erase them, which is why somebody who dropped and came
    // back appeared twice in the standings: they were admitted as a stranger
    // and handed a fresh phone number, and the scoreboard is keyed by that
    // number. Remembering the seat is what lets them have it back.
    if (_phase != HostPhase.lobby) {
      if (_phase == HostPhase.placing) {
        _layoutAgainWithoutThem(record);
      } else {
        // Mid-game: leave the world alone (its slice just goes dark) rather
        // than silently rearranging a board people have physically laid out.
        //
        // Said only here. During placement the board *is* rebuilt, on its own,
        // and this advice would have been both wrong and in the way — a banner
        // telling the table to re-calibrate, over a screen already showing it
        // the new arrangement.
        _warning =
            '${record.label} disconnected — re-calibrate to rebuild the '
            'board.';
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
  /// arrange a single phone, so a two-phone game would have quietly gone ahead as a
  /// one-player game after its second player walked off.
  void _layOutAgain({required String because}) {
    final game = _game;
    // Forward only. The playlist is played through once, so a table that has
    // shrunk past what this game needs carries on down the list rather than
    // doubling back — and if nothing further suits it, the lobby is the honest
    // answer rather than replaying something.
    final index = game != null && game.manifest.fits(_present.length)
        ? _gameIndex
        : GameCatalog.playableIndexFrom(
            _gameIndex + 1,
            _present.length,
            skipping: _skipping,
            order: _order,
          );

    if (index == null) {
      // Nowhere forward to go, so the table is told to its face rather than
      // being dropped into the lobby to work out for itself why the round it
      // was setting up vanished.
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

    // Said every time the table changes shape, not only when the game does.
    // Everybody is about to be asked to put their phone somewhere new and the
    // Ready they already gave has been thrown away; being told only when the
    // *game* changed would leave that looking like the app forgetting itself.
    _tableChange = TableChange(
      who: because,
      nextGame: _order[index].manifest.title,
    );
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
    _finishRound(GameOutcome.draw(summary: '${record.label} dropped out'));
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
        record.metrics = DeviceMetrics.fromJson(
          msg['metrics'] as Map<String, dynamic>,
        );
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

  /// A phone says its screen was covered by something that was not the player
  /// leaving. On its own that means little; see [NameDropDetector].
  ///
  /// Only while a layout exists. In the lobby the phones are in pockets and on
  /// chair arms, nowhere near each other, and [_dangerPairs] still describes
  /// whatever table the last round was played on — so the one place a stale
  /// set could do harm is the one place this refuses to look at it.
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

    // Both ends, because the interaction takes two: if it fired, neither of
    // them had the setting off, whatever either of them told us.
    for (final phoneId in [pair.$1, pair.$2]) {
      _phoneById(phoneId)?.link.send({'type': HostMsg.nameDropSuspected});
    }
  }

  /// Somebody tapped a neighbour's colour on the placement screen: make that
  /// neighbour speak.
  ///
  /// Only while the table is being laid out. Mid-round the same message would
  /// be a way to drop a noise into somebody else's game, and in the lobby the
  /// phones are in pockets where a voice answers nothing.
  ///
  /// Poking yourself does nothing. The sound is meant to travel across the
  /// table, and a phone that can already make its own noise has no use for a
  /// round trip to ask for one.
  void _handlePoke(PhoneRecord from, String? phoneId) {
    if (_phase != HostPhase.placing) return;
    if (phoneId == null || phoneId == from.phoneId) return;

    final target = _phoneById(phoneId);
    if (target == null) return;

    // Happy or sad, by coin toss, because the point is to hear *which* phone
    // answered rather than what it thought of being asked.
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

  // ----------------------------------------------------------- the round

  /// Which way the current round was started.
  RoundMode get mode => _mode;

  /// What comes after this round — null for a one-off, or when nothing else
  /// fits the table.
  MultiscreenGame? get nextGame => _mode == RoundMode.oneOff
      ? null
      : GameCatalog.playableFrom(
          _gameIndex + 1,
          _present.length,
          skipping: _skipping,
          order: _order,
        );

  /// The playlist has been played out: this round was the last game that fits
  /// the table, and there is nothing after it.
  ///
  /// Deliberately not the same question as `nextGame == null`, which is also
  /// true of a single game started from the games list. That one ends where it
  /// started — at the list — and has no run to total up.
  bool get runIsOver => _mode == RoundMode.playlist && nextGame == null;

  /// One named game, then back to the lobby.
  ///
  /// Everything between the call and the placement screen happens here, with no
  /// screen in between: the game already knows where the phones go.
  ///
  /// Deliberately ignores the tick list. It names a game outright, which is a
  /// stronger statement than a tick — and the way to play exactly one game from
  /// the list is to be the only thing ticked in it.
  ///
  /// **Nothing in the app calls this, and nothing ever has.** No screen has
  /// reached it in the whole history of the repository: the lobby settled on a
  /// tick list, and naming a game outright never grew a button. What it is, in
  /// practice, is the shortcut most of the test suite uses to put one specific
  /// game on the table without ticking eleven others off first — which is worth
  /// keeping, and worth being honest about.
  ///
  /// Hence [visibleForTesting]. It is not decoration: this method skips the
  /// tick list, and the paywall lived inside the tick list until recently, so a
  /// screen wired to it would have handed every Premium game to a free host. The
  /// annotation turns "no production code calls this" from something somebody
  /// has to keep checking into something the analyzer refuses to let through.
  /// [_startGame] guards the paywall as well, for every caller — but a call that
  /// cannot be written is better than a call that is caught.
  ///
  /// Note also that this is the only thing that ever sets [RoundMode.oneOff], so
  /// that whole branch — [nextGame] returning null, [runIsOver] staying false —
  /// is currently reachable only from tests. Either a screen should want it, or
  /// the mode should go; that is a product call, not a cleanup.
  @visibleForTesting
  void startGame(MultiscreenGame game) {
    if (!canStart) return;
    if (!game.manifest.fits(_present.length)) return;
    // Naming a game outright is a stronger statement than a tick, but it is not
    // a stronger statement than having paid. [_skipping] is where the paywall
    // lives, and "ignores the tick list" must not quietly mean "ignores that
    // too" — see [_mayStart].
    if (!_mayStart(game)) return;
    final index = _order.indexWhere((g) => g.manifest.id == game.manifest.id);
    if (index < 0) return;
    _mode = RoundMode.oneOff;
    // No run to be part of. A one-off that the table outgrows falls back to the
    // ticked list rather than to a run it was never in.
    _runGames = null;
    _startGame(index);
  }

  /// The run: every ticked game that fits, in order. The **Play** button.
  void startRound() {
    if (!canStart) return;
    _mode = RoundMode.playlist;

    // The run is settled here, once, and not asked again for the rest of it.
    // Read before it is stored — [runningOrder] is answered against the ticks
    // until there is a run to answer against instead.
    _runGames = {for (final game in runningOrder) game.manifest.id};

    // And the order it is played in, dealt fresh every Play. Only the order:
    // what is in the run was settled on the line above.
    _order = List.of(GameCatalog.playlist)..shuffle(_random);

    // The one moment the whole table is asked to look at the same thing.
    _introPending = true;

    // Always from the top: a run is the whole list, not a resumption of one
    // somebody abandoned.
    _startGame(
      GameCatalog.playableIndexFrom(
        0,
        _present.length,
        skipping: _skipping,
        order: _order,
      )!,
    );
  }

  /// Whether this host is allowed to put [game] on the table at all.
  ///
  /// The paywall as a fact about the game and the receipt, with nothing about
  /// tick lists or table sizes mixed in. [_skipping] answers "what should we
  /// offer"; this answers "may this start", and the two are different questions
  /// that happened to share an implementation until one entry point wanted the
  /// first and got neither.
  bool _mayStart(MultiscreenGame game) =>
      !game.manifest.isPremium || isPremiumUnlocked;

  void _startGame(int index) {
    final game = _order[index];

    // The last gate before a premium game reaches a screen, and the reason it
    // is here rather than only at the callers: every way a round can begin —
    // the Play button, a named one-off, advancing through the run, a replay —
    // funnels through this method. A check here cannot be routed around by the
    // next feature that wants to start a game, which is exactly how the one-off
    // path came to skip the paywall in the first place.
    //
    // Deliberately before any state is touched, so a refusal is a no-op rather
    // than a half-started round. In practice the playlist paths cannot reach
    // this — they pick their index through [_skipping], which already excludes
    // premium for a free host — so this firing means a caller found a new way
    // in, and the right answer is to do nothing at all.
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
      _runGames = null;
      _phase = HostPhase.lobby;
      _releaseAwayColours();
      _broadcastLobby();
      notifyListeners();
      return;
    }

    // Measured on the plan the optimizer *returned*, so these are the pairs it
    // could not save — a middle phone in a row of three has its top against
    // somebody whichever way it is turned. Those are the only places NameDrop
    // can still fire, and knowing which they are is what lets an interruption
    // be told from a stray thumb.
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
        // The compiled truth about where every phone ended up. The placement
        // diagram is drawn from this, so what people are shown is the layout
        // the game actually chose rather than a guess reconstructed from the
        // lobby's join order.
        'slices': [for (final s in solved.slices) s.toJson()],
        // Coloured stripes marking which edge meets which neighbour. Computed
        // once by the compiler; every phone draws the same answer.
        'links': [for (final l in solved.links) l.toJson()],
        'instruction': solved.instruction,
        // Every phone plays the curtain, so every phone has to be told in the
        // same message that carries the board it hides.
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

    // A game whose sim will not build is reported, not left hanging.
    //
    // `planBoard` is guarded where it runs, but a game can also refuse at
    // `createSim` — it is the first place a game sees the *compiled* board,
    // and the first place it can discover the table is not one it can play on.
    // Without this the exception escapes mid-transition, the phase never
    // advances, and every phone sits on the placement screen forever with
    // nothing on any screen to say why.
    final audio = RoundAudio();
    final GameSim sim;
    try {
      sim = game.createSim(
        solved.contextFor(scores, audio: audio, hostPhoneId: hostPhoneId),
      );
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
    // A game is allowed to ask for a sound while it is being built — a theme,
    // a whistle — and those cues are queued before the first step. Sent after
    // `start`, so no phone is told to play something for a round it has not
    // been told has begun.
    _flushAudio();

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
    // After the state, so a cue and the picture that caused it carry the same
    // timestamp and land together on every phone.
    _flushAudio();

    final outcome = sim.outcome;
    if (outcome != null) _finishRound(outcome);
  }

  /// Send whatever the sim asked to be heard.
  ///
  /// Stamped here rather than at the call site, with the sim time of the step
  /// that raised it — which is the timestamp of the snapshot broadcast in the
  /// same tick. That is what lets a phone fire the sound at the instant of the
  /// shared timeline the picture arrives at, instead of the moment the packet
  /// happened to land.
  ///
  /// A general cue goes to the host's phone **only**. Broadcasting it would
  /// have eight phones playing one clip at eight distances, which is the flam
  /// the two verbs exist to avoid.
  void _flushAudio() {
    final audio = _audio;
    if (audio == null || !audio.hasPending) return;

    final at = simTimeMs;
    for (final command in audio.drain()) {
      final msg = {'type': HostMsg.sound, ...command.toJson(at)};
      if (command.isBroadcast) {
        // The end of the round. Every phone may be holding a sound of its own,
        // and each of them already knows which ones it was told to keep.
        _broadcast(msg);
        continue;
      }
      final phoneId = command.phoneId;
      if (phoneId == null) {
        // The table's speaker, or nothing at all when the host is headless.
        // Not a broadcast, and not a fallback to somebody else's phone.
        _localRecord?.link.send(msg);
      } else {
        // A phone that has gone is silence: no fallback, because a sound from
        // the wrong side of the table is worse information than none.
        _phoneById(phoneId)?.link.send(msg);
      }
    }
  }

  /// Everything this round started goes quiet, and the queue goes with it.
  ///
  /// Called from every teardown — the next game, a re-calibrate, the lobby, the
  /// end of the run — so a game never has to remember, and a round abandoned
  /// halfway still stops making noise. Anything a game marked `persist` was
  /// handed to the session and plays on.
  ///
  /// **Not from [_finishRound].** A round ending is the moment a game plays its
  /// win sting, and silencing there would cancel the cue raised by the very
  /// step that ended the round. The results screen is still part of the round
  /// as far as sound is concerned; it goes quiet on the way out of it.
  void _silenceRound() {
    final audio = _audio;
    if (audio == null) return;
    audio.stopRoundSounds();
    _flushAudio();
    _audio = null;
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
      // What follows this screen, for the phones that have no button to press.
      // A joiner cannot tell a spent playlist from a one-off — both arrive with
      // no next game — and the two end in different places.
      'runOver': runIsOver,
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
    _silenceRound();
    _sim?.dispose();
    _sim = null;
    _layout = null;
    // Deliberately not dropped: a phone that has gone quiet keeps its place on
    // the roster, so its score is still there when it comes back.
    final index = GameCatalog.playableIndexFrom(
      _gameIndex + 1,
      _present.length,
      skipping: _skipping,
      order: _order,
    );
    if (index == null) {
      // Only reachable by somebody dropping out between the button being drawn
      // and being tapped — the button that leads here is only offered when
      // there *is* a next game. Either way the run is over, and a run that is
      // over ends at the standings.
      showScoreboard();
      return;
    }
    _startGame(index);
  }

  /// The run is over: put the final standings on every screen.
  ///
  /// The end of a playlist, and the only thing between the last round and the
  /// lobby. It is a phase rather than a screen the host opens locally because
  /// the standings are the *table's* — six people leaning in to see who won is
  /// the point, and one of them reading it on the host's phone while the other
  /// five look at "back to the games" is not.
  ///
  /// Reached from two endings: the last round of the list finishing, and the
  /// table shrinking past what anything left in the list can be played by. Both
  /// tear the round down here, so neither needs to do it on its way in.
  void showScoreboard() {
    if (_phase == HostPhase.scoreboard) return;
    _loop?.cancel();
    _loop = null;
    _silenceRound();
    _sim?.dispose();
    _sim = null;
    _layout = null;
    _warning = null;
    // Read, by getting here. Left set it would be routed ahead of this screen
    // and the button that led here would look like it had done nothing.
    _tableChange = null;
    _outcome = null;
    _game = null;
    // The run this was the end of. Cleared here as well as at the lobby, so the
    // standings screen is already answering for the *next* run — which is the
    // ticked list, whatever this one turned out to consist of.
    _runGames = null;
    // Deliberately not dropped: a phone that has gone quiet keeps its place on
    // the roster, so its score is still on the board it is being totalled on.
    for (final p in _phones) {
      p.confirmed = false;
    }
    _phase = HostPhase.scoreboard;
    _releaseAwayColours();
    // Forced, because this screen *is* the scores: a phone whose last snapshot
    // was diffed away has nothing else to draw.
    _broadcastScores(force: true);
    _broadcastLobby();
    _updateBeacon();
    notifyListeners();
  }

  /// Put the round back to its opening position.
  ///
  /// A reset counts as a round boundary for sound: a loop still running from
  /// the previous attempt is not the opening position. The emitter survives —
  /// unlike a teardown, the same round carries on and its handles stay valid.
  void resetRound() {
    _sim?.reset();
    _audio?.stopRoundSounds();
    _flushAudio();
  }

  /// Back to the arrangement for the *same* game — the debug panel's
  /// "re-calibrate", for when a measurement was wrong.
  void recalibrate() {
    _loop?.cancel();
    _loop = null;
    _silenceRound();
    _sim?.dispose();
    _sim = null;
    _warning = null;
    _tableChange = null;
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
    _silenceRound();
    _sim?.dispose();
    _sim = null;
    _layout = null;
    _warning = null;
    // Read, and acted on by getting here — so it goes, on every phone, via the
    // broadcast at the bottom. Left set it would survive the very button that
    // exists to clear it.
    _tableChange = null;
    _outcome = null;
    _game = null;
    // Deliberately not dropped: a phone that has gone quiet keeps its place on
    // the roster, so its score is still there when it comes back.
    for (final p in _phones) {
      p.confirmed = false;
    }
    _phase = HostPhase.lobby;
    _releaseAwayColours();
    _mode = RoundMode.playlist;
    // Back to the top of the list. The playlist is played through once, so
    // without this a second Play would start from wherever the last one
    // stopped — and after a full run, from past the end, which reads as "no
    // game fits this table".
    _gameIndex = 0;
    _order = GameCatalog.playlist;
    // And back to the ticks. The next run is worked out from the table as it
    // will be then, not as it was when the last one started.
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
      // Which seat is running the session. Nothing can derive it: board order
      // is not join order, and a host that reconnects does not take the first
      // seat back. Games ask, because a game may want to show whose table
      if (hostPhoneId != null) 'host': hostPhoneId,
      // The table changing shape is news for every phone, not only the one
      // running the session — everybody is about to be asked to move.
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
