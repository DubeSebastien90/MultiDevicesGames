import 'dart:async';

import 'package:flutter/foundation.dart';

import '../game/game_config.dart';
import '../model/device_metrics.dart';
import '../net/protocol.dart';
import '../net/transport.dart';
import '../net/websocket_transport.dart';
import 'layout_solver.dart';
import 'slingshot_sim.dart';

enum HostPhase { idle, lobby, placing, playing }

/// One connected phone, from the host's point of view.
class PhoneRecord {
  PhoneRecord({required this.phoneId, required this.link});

  final String phoneId;
  final PeerLink link;

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
  HostSession({HostTransport? transport})
    : _transport = transport ?? WebSocketHostTransport();

  final HostTransport _transport;

  final _clock = Stopwatch();
  final _phones = <PhoneRecord>[];
  final _subs = <StreamSubscription<dynamic>>[];

  HostPhase _phase = HostPhase.idle;
  Uri? _address;
  SlingshotSim? _sim;
  BoardLayout? _layout;
  Timer? _loop;
  String? _warning;

  int _nextPhoneNumber = 1;
  int _stepCount = 0;
  double _accumulatorMs = 0;
  int _lastClockUs = 0;

  HostPhase get phase => _phase;
  Uri? get address => _address;
  BoardLayout? get layout => _layout;

  /// Ordered left-to-right; this order *is* the physical arrangement.
  List<PhoneRecord> get phones => List.unmodifiable(_phones);

  String? get warning => _warning;

  /// Sim time in ms — the timeline every snapshot is stamped with.
  double get simTimeMs => _stepCount * (1000 / GameConfig.simHz);

  bool get canPlacePhones =>
      _phase == HostPhase.lobby &&
      _phones.isNotEmpty &&
      _phones.every((p) => p.calibrated && p.connected);

  // ------------------------------------------------------------ lifecycle

  Future<Uri> start() async {
    _clock.start();
    final uri = await _transport.start();
    _address = uri;
    _phase = HostPhase.lobby;
    _subs.add(_transport.onPeer.listen(_attachPeer));
    notifyListeners();
    return uri;
  }

  /// Adds the host's own screen as a peer. It then goes through the identical
  /// handshake, layout and interpolation path as any remote phone — which is
  /// what keeps every screen on one shared timeline.
  void addLocalPeer(PeerLink peer) => _attachPeer(peer);

  void _attachPeer(PeerLink link) {
    if (_phase == HostPhase.playing || _phase == HostPhase.placing) {
      // Joining mid-game would invalidate the board everyone already placed
      // themselves for. Turn them away with an explanation instead.
      link.send({
        'type': HostMsg.welcome,
        'rejected': true,
        'reason': 'Game already set up. Ask the host to re-calibrate.',
      });
      Future<void>.delayed(const Duration(milliseconds: 300), link.close);
      return;
    }

    final record = PhoneRecord(
      phoneId: 'p${_nextPhoneNumber++}',
      link: link,
    );
    _phones.add(record);

    _subs.add(link.onMessage.listen(
      (msg) => _handleMessage(record, msg),
      onDone: () => _handleDisconnect(record),
      onError: (Object _) => _handleDisconnect(record),
    ));

    link.send({'type': HostMsg.welcome, 'phoneId': record.phoneId});
    _broadcastLobby();
    notifyListeners();
  }

  void _handleDisconnect(PhoneRecord record) {
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
    notifyListeners();
  }

  void _handleMessage(PhoneRecord record, Map<String, dynamic> msg) {
    switch (msg['type'] as String?) {
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
    if (_phase != HostPhase.lobby) return;
    if (index < 0 || index >= _phones.length) return;
    if (target < 0 || target >= _phones.length) return;
    final p = _phones.removeAt(index);
    _phones.insert(target, p);
    _broadcastLobby();
    notifyListeners();
  }

  /// Builds the world from the calibration data and tells each phone where to
  /// sit. Play does not start until every phone confirms.
  void sendPlacement() {
    if (!canPlacePhones) return;

    final solved = const LayoutSolver().solve([
      for (final p in _phones) CalibratedPhone(p.phoneId, p.metrics!),
    ]);
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
      });
    }
    _broadcastLobby();
    notifyListeners();
  }

  void _beginPlay() {
    final solved = _layout;
    if (solved == null) return;

    final sim = SlingshotSim(coverage: solved.coverage);
    _sim = sim;
    _phase = HostPhase.playing;
    _stepCount = 0;
    _accumulatorMs = 0;
    _lastClockUs = _clock.elapsedMicroseconds;

    _broadcast({
      'type': HostMsg.worldInit,
      'board': solved.coverage.board.toJson(),
      'anchor': {'x': sim.anchor.x, 'y': sim.anchor.y},
      'entities': [for (final s in sim.specs) s.toJson()],
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

    _broadcast({
      'type': HostMsg.state,
      'tick': sim.tick,
      't': simTimeMs,
      'entities': [for (final e in sim.entityStates()) e.toJson()],
      'sling': sim.slingState().toJson(),
    });
  }

  void resetBird() => _sim?.reset();

  /// Tear the world down and go back to collecting phones.
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

  void _broadcastLobby() {
    _broadcast({
      'type': HostMsg.lobby,
      'phase': _phase.name,
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
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _transport.dispose();
    super.dispose();
  }
}
