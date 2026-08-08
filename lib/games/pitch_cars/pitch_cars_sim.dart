import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/model/player_color.dart';
import '../../sdk/physics/forge2d_game_sim.dart';
import '../../sdk/render/shape_view.dart';
import 'pitch_cars_config.dart';
import 'track.dart';

part 'sim_track.dart';
part 'sim_input.dart';
part 'sim_progress.dart';
part 'sim_contact.dart';

/// Flick your car around a randomized track. Turn-based: exactly one
/// player's car may be flicked at a time, in join order.
///
/// Input is gated by proximity to the current turn's car, never by
/// [TouchEvent.phoneId] — the board spans multiple phones, so a car can end
/// up under a different phone's screen than the one its owner joined from.
class PitchCarsSim extends Forge2DGameSim {
  PitchCarsSim(super.context, {math.Random? random})
    : _random = random ?? math.Random() {
    track = TrackGenerator.generate(
      slices: context.slices,
      random: _random,
    );
    _buildTrackEntities();
    _buildFinishLineEntities();
    _order = context.phoneIds;
    _colorOf = {
      for (final s in context.slices)
        if (s.color != null) s.phoneId: s.color!,
    };
    _placeCars();
    _preTurnPosition = carOf(currentTurn).position.clone();
    for (final id in _order) {
      final pos = carOf(id).position;
      _lastOnTrack[id] = pos.clone();
      _rawProgress[id] = track.progressAt(pos.x, pos.y);
      _progress[id] = 0;
    }
    world.setContactListener(_CarContactListener(this));
  }

  final math.Random _random;
  late final PitchTrack track;
  late final List<String> _order;
  late final Map<String, PlayerColor> _colorOf;
  final _trackEntities = <Entity>[];

  late int _currentIndex = 0;
  String get currentTurn => _order[_currentIndex];

  final _lastHitBy = <String, String?>{};
  final _lastHitAt = <String, Duration>{};
  final _lastOnTrack = <String, Vector2>{};
  final _rawProgress = <String, double>{};
  final _progress = <String, double>{};
  late Vector2 _preTurnPosition;

  String? _draggingPhoneId;
  Vector2? _pull;
  bool _moving = false;
  Duration _sinceLaunch = Duration.zero;
  Duration _atRest = Duration.zero;

  /// Reset whenever the current car moves more than
  /// [PitchCarsConfig.stallDisplacement] away — feeds the stall watchdog.
  Vector2? _stallAnchor;
  Duration _sinceStallAnchor = Duration.zero;

  String? _winner;
  bool _awarded = false;

  Body carOf(String id) => bodyOf(id)!;

  @override
  void onTouch(TouchEvent touch) {
    if (_winner != null || _moving) return;
    final car = carOf(currentTurn);
    final p = Vector2(touch.worldX, touch.worldY);

    switch (touch.phase) {
      case TouchPhase.down:
        if (_draggingPhoneId != null) return;
        final reach = PitchCarsConfig.carRadius + PitchCarsConfig.grabSlack;
        if (p.distanceTo(car.position) > reach) return;
        _draggingPhoneId = touch.phoneId;
        _pull = car.position.clone();

      case TouchPhase.move:
        if (_draggingPhoneId != touch.phoneId || _pull == null) return;
        _pull = _clampPull(p);

      case TouchPhase.up:
        if (_draggingPhoneId != touch.phoneId || _pull == null) return;
        _launch();
    }
  }

  @override
  void step(double dt) {
    super.step(dt);
    if (_winner != null) return;

    _resolveOffTrack();
    _updateProgress();

    if (_moving) {
      final elapsed = Duration(microseconds: (dt * 1e6).round());
      _sinceLaunch += elapsed;
      var maxSpeed = 0.0;
      for (final id in _order) {
        final speed = carOf(id).linearVelocity.length;
        if (speed > maxSpeed) maxSpeed = speed;
      }
      _atRest = maxSpeed < PitchCarsConfig.restSpeed
          ? _atRest + elapsed
          : Duration.zero;

      // Angular damping should stop a car spinning-in-place well before
      // this, but this watchdog is the actual guarantee: force the turn to
      // end if the car hasn't translated in a while, regardless of why.
      final currentPos = carOf(currentTurn).position;
      if (_stallAnchor == null ||
          currentPos.distanceTo(_stallAnchor!) >
              PitchCarsConfig.stallDisplacement) {
        _stallAnchor = currentPos.clone();
        _sinceStallAnchor = Duration.zero;
      } else {
        _sinceStallAnchor += elapsed;
      }

      if (_atRest >= PitchCarsConfig.restDelay ||
          _sinceLaunch >= PitchCarsConfig.maxFlightTime ||
          _sinceStallAnchor >= PitchCarsConfig.stallTimeout) {
        _endTurn();
      }
    }

    if (_winner != null && !_awarded) {
      _awarded = true;
      context.scores.award(_winner!, 1);
    }
  }

  String get _winnerLabel =>
      context.slices.firstWhere((s) => s.phoneId == _winner).label;

  @override
  Iterable<Entity> get entities sync* {
    // Track segments first so cars (from super.entities) paint on top.
    yield* _trackEntities;
    yield* super.entities;
  }

  @override
  Map<String, Object?> get sharedState => {
    'currentTurn': _winner == null ? currentTurn : null,
    'winner': _winner,
    for (final id in _order)
      'progress_$id': track.length < 1e-9
          ? 0.0
          : double.parse(
              ((_progress[id] ?? 0) / track.length)
                  .clamp(0.0, 1.0)
                  .toStringAsFixed(3),
            ),
    // Pull point in world coords while aiming, null once released/idle —
    // the view draws the launch arrow from this to the current car.
    'pullX': _pull == null ? null : double.parse(_pull!.x.toStringAsFixed(3)),
    'pullY': _pull == null ? null : double.parse(_pull!.y.toStringAsFixed(3)),
    'moving': _moving,
  };

  @override
  GameOutcome? get outcome => _winner == null
      ? null
      : GameOutcome.won(summary: '$_winnerLabel wins the race');

  @override
  void reset() {
    _currentIndex = 0;
    _draggingPhoneId = null;
    _pull = null;
    _moving = false;
    _winner = null;
    _awarded = false;
    _sinceLaunch = Duration.zero;
    _atRest = Duration.zero;
    _stallAnchor = null;
    _sinceStallAnchor = Duration.zero;
    _lastHitBy.clear();
    _lastHitAt.clear();

    for (var i = 0; i < _order.length; i++) {
      final pos = _startPositionFor(i);
      final car = carOf(_order[i])
        ..setTransform(pos, 0)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0
        ..setAwake(true);
      _lastOnTrack[_order[i]] = car.position.clone();
      _rawProgress[_order[i]] = track.progressAt(
        car.position.x,
        car.position.y,
      );
      _progress[_order[i]] = 0;
    }
    _preTurnPosition = carOf(currentTurn).position.clone();
  }
}
