import 'dart:math' as math;

import 'package:forge2d/forge2d.dart';

import '../../sdk/audio/sound_cue.dart';
import '../../sdk/contract/entity.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/model/player_color.dart';
import '../../sdk/physics/forge2d_game_sim.dart';
import '../../sdk/render/shape_view.dart';
import 'corner_walls.dart';
import 'pitch_cars_config.dart';
import 'pitch_cars_scale.dart';
import 'track.dart';

part 'sim_track.dart';
part 'sim_input.dart';
part 'sim_progress.dart';
part 'sim_contact.dart';

class PitchCarsSim extends Forge2DGameSim {
  PitchCarsSim(super.context, {math.Random? random})
    : _random = random ?? math.Random() {
    scale = PitchCarsScale.forPlayers(context.slices.length);
    track = TrackGenerator.generate(
      slices: context.slices,
      random: _random,
      scale: scale,
    );
    _buildTrackEntities();
    _buildCornerWalls();
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

  late final PitchCarsScale scale;

  late final PitchTrack track;
  late final List<String> _order;
  late final Map<String, PlayerColor> _colorOf;
  final _trackEntities = <Entity>[];
  final _fixtureOf = <String, Fixture>{};

  late int _currentIndex = 0;
  String get currentTurn => _order[_currentIndex];

  final _lastHitBy = <String, String?>{};
  final _lastHitAt = <String, Duration>{};
  final _lastOnTrack = <String, Vector2>{};

  final _fallenFor = <String, double>{};

  final _fallTarget = <String, Vector2>{};

  final _fallAngle = <String, double>{};

  final _fallVisualFor = <String, double>{};
  final _rawProgress = <String, double>{};
  final _progress = <String, double>{};
  late Vector2 _preTurnPosition;

  String? _draggingPhoneId;

  SoundHandle? _holdSound;

  double _sinceCrash = PitchCarsConfig.crashCooldownSeconds;

  Vector2? _dragOrigin;
  Vector2? _pull;
  bool _moving = false;
  Duration _sinceLaunch = Duration.zero;
  Duration _atRest = Duration.zero;

  Vector2? _stallAnchor;
  Duration _sinceStallAnchor = Duration.zero;

  final _finished = <String>{};
  final _finishOrder = <String>[];
  bool get _roundOver => _finished.length >= _order.length;
  bool _awarded = false;
  GameOutcome? _outcome;

  Body carOf(String id) => bodyOf(id)!;

  @override
  void onTouch(TouchEvent touch) {
    if (_roundOver || _moving) return;
    final car = carOf(currentTurn);
    final p = Vector2(touch.worldX, touch.worldY);

    switch (touch.phase) {
      case TouchPhase.down:
        if (_draggingPhoneId != null) return;

        final reach = scale.carRadius + scale.grabSlack;
        _dragOrigin = p.distanceTo(car.position) <= reach ? null : p.clone();
        _draggingPhoneId = touch.phoneId;
        _pull = _preTurnPosition.clone();
        _holdSound = _playOn(touch.phoneId, PitchCarsConfig.hold);

      case TouchPhase.move:
        if (_draggingPhoneId != touch.phoneId || _pull == null) return;

        final origin = _dragOrigin ?? _preTurnPosition;
        _pull = _clampPull(_preTurnPosition + (p - origin));
        _faceTheShot(car);

      case TouchPhase.up:
        if (_draggingPhoneId != touch.phoneId || _pull == null) return;
        _launch();
    }
  }

  SoundHandle? _playOn(String phoneId, SoundCue cue, {double volume = 1.0}) {
    final player = context.roster.byPhone(phoneId);
    if (player == null) return null;
    return context.audio.playOnPhone(player, cue, volume: volume);
  }

  void _crashAt(double x, double y) {
    if (_sinceCrash < PitchCarsConfig.crashCooldownSeconds) return;
    final phone = context.nearestPhone(x, y);
    if (phone == null) return;
    _sinceCrash = 0;
    _playOn(phone, PitchCarsConfig.crash, volume: PitchCarsConfig.crashVolume);
  }

  void _brake(double dt) {
    for (final id in _order) {
      if (_finished.contains(id) || _fallenFor.containsKey(id)) continue;
      final car = carOf(id);
      final v = car.linearVelocity;
      final speed = v.length;
      if (speed == 0 || speed >= scale.brakeSpeed) continue;
      final slower = speed - scale.brakeDecel * dt;
      if (slower <= 0) {
        car
          ..linearVelocity = Vector2.zero()
          ..angularVelocity = 0;
      } else {
        car.linearVelocity = v * (slower / speed);
      }
    }
  }

  void _stopHold() {
    final hold = _holdSound;
    if (hold == null) return;
    _holdSound = null;
    context.audio.stopSound(hold, fade: PitchCarsConfig.holdFadeOut);
  }

  @override
  void step(double dt) {
    _sinceCrash += dt;
    super.step(dt);
    _brake(dt);
    if (_roundOver) {
      if (!_awarded) {
        _awarded = true;
        _awardPoints();
      }
      return;
    }

    _resolveOffTrack(dt);
    _updateProgress();

    if (_moving) {
      final elapsed = Duration(microseconds: (dt * 1e6).round());
      _sinceLaunch += elapsed;
      var maxSpeed = 0.0;
      for (final id in _order) {
        if (_finished.contains(id)) continue;

        if (_fallenFor.containsKey(id)) continue;
        final speed = carOf(id).linearVelocity.length;
        if (speed > maxSpeed) maxSpeed = speed;
      }

      _atRest = maxSpeed == 0 ? _atRest + elapsed : Duration.zero;

      final currentPos = carOf(currentTurn).position;
      if (_stallAnchor == null ||
          currentPos.distanceTo(_stallAnchor!) > scale.stallDisplacement) {
        _stallAnchor = currentPos.clone();
        _sinceStallAnchor = Duration.zero;
      } else {
        _sinceStallAnchor += elapsed;
      }

      if (_fallenFor.isEmpty &&
          (_atRest >= PitchCarsConfig.restDelay ||
              _sinceLaunch >= PitchCarsConfig.maxFlightTime ||
              _sinceStallAnchor >= PitchCarsConfig.stallTimeout)) {
        _endTurn();
      }
    }
  }

  void _awardPoints() {
    final paid = context.scores.awardPlacements([
      for (final id in _finishOrder) {id},
    ]);
    final lines = <String, String>{
      for (var i = 0; i < _finishOrder.length; i++)
        _finishOrder[i]:
            '${_placeLabel(i + 1)} — +${paid[_finishOrder[i]]} pts',
    };
    _outcome = GameOutcome.contest(
      winners: {_finishOrder.first},
      summary: '$_winnerLabel wins the race',
      lines: lines,
    );
  }

  static String _placeLabel(int place) {
    if (place % 100 >= 11 && place % 100 <= 13) return '${place}th';
    return switch (place % 10) {
      1 => '${place}st',
      2 => '${place}nd',
      3 => '${place}rd',
      _ => '${place}th',
    };
  }

  String get _winnerLabel =>
      context.slices.firstWhere((s) => s.phoneId == _finishOrder.first).label;

  @override
  Iterable<Entity> get entities sync* {
    yield* _trackEntities;
    yield* super.entities;
  }

  @override
  Map<String, Object?> get sharedState => {
    'maxPull': scale.maxPull,
    'currentTurn': _roundOver ? null : currentTurn,
    'winner': _finishOrder.isEmpty ? null : _finishOrder.first,
    for (final id in _order) 'finished_$id': _finished.contains(id),
    for (final entry in _fallVisualFor.entries)
      'fall_${entry.key}': double.parse(
        ((entry.value - PitchCarsConfig.fallVisualLagSeconds) /
                PitchCarsConfig.fallSeconds)
            .clamp(0.0, 1.0)
            .toStringAsFixed(3),
      ),
    for (final id in _order)
      'progress_$id': track.length < 1e-9
          ? 0.0
          : double.parse(
              ((_progress[id] ?? 0) / track.length)
                  .clamp(0.0, 1.0)
                  .toStringAsFixed(3),
            ),
    'pullX': _pull == null ? null : double.parse(_pull!.x.toStringAsFixed(3)),
    'pullY': _pull == null ? null : double.parse(_pull!.y.toStringAsFixed(3)),
    'anchorX': _dragOrigin == null
        ? null
        : double.parse(_dragOrigin!.x.toStringAsFixed(3)),
    'anchorY': _dragOrigin == null
        ? null
        : double.parse(_dragOrigin!.y.toStringAsFixed(3)),
    'moving': _moving,
  };

  @override
  GameOutcome? get outcome => _outcome;

  @override
  void reset() {
    _currentIndex = 0;
    _draggingPhoneId = null;
    _holdSound = null;
    _sinceCrash = PitchCarsConfig.crashCooldownSeconds;
    _dragOrigin = null;
    _pull = null;
    _moving = false;
    _finished.clear();
    _finishOrder.clear();
    _awarded = false;
    _outcome = null;
    _sinceLaunch = Duration.zero;
    _atRest = Duration.zero;
    _stallAnchor = null;
    _sinceStallAnchor = Duration.zero;
    _lastHitBy.clear();
    _lastHitAt.clear();

    _fallenFor.clear();
    _fallTarget.clear();
    _fallAngle.clear();
    _fallVisualFor.clear();

    for (var i = 0; i < _order.length; i++) {
      final pos = _startPositionFor(i);
      final car = carOf(_order[i])
        ..setTransform(pos, 0)
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0
        ..setAwake(true);
      _fixtureOf[_order[i]]?.setSensor(false);
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
