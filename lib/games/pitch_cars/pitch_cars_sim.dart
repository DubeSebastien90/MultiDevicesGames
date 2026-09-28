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

/// Flick your car around a randomized track. Turn-based: exactly one
/// player's car may be flicked at a time, in join order.
///
/// Input is never gated by [TouchEvent.phoneId] — the board spans multiple
/// phones, so a car can end up under a different phone's screen than the one
/// its owner joined from. Nor is it gated by where the touch lands: proximity
/// to the car only picks *which* point the draw is measured from.
class PitchCarsSim extends Forge2DGameSim {
  PitchCarsSim(super.context, {math.Random? random})
    : _random = random ?? math.Random() {
    // Everything the table's size changes, settled once and read from here on.
    // Derived from the slices rather than the players because it is the *road*
    // this sets the shape of, and the road is built from the board.
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

  /// How big this table's race is drawn and how far its flicks carry.
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

  /// Cars currently over the edge, and how long they have been falling.
  /// Membership is the state: absent means on the road.
  final _fallenFor = <String, double>{};

  /// Where each falling car will reappear, decided when it went over rather
  /// than when it lands — by then the turn may have moved on.
  final _fallTarget = <String, Vector2>{};

  /// Which way each falling car was pointing when it went over, so it comes
  /// back the way it was going rather than wherever the tumble left it.
  final _fallAngle = <String, double>{};

  /// The fall as the phones should see it: a clock started with the fall that
  /// outlives the landing by [PitchCarsConfig.fallVisualLagSeconds], since
  /// that is how far behind the sim they draw the car.
  final _fallVisualFor = <String, double>{};
  final _rawProgress = <String, double>{};
  final _progress = <String, double>{};
  late Vector2 _preTurnPosition;

  String? _draggingPhoneId;

  /// The hold sound of the aim being drawn, so the release can cut it short.
  SoundHandle? _holdSound;

  /// Seconds since the last crash sounded — see
  /// [PitchCarsConfig.crashCooldownSeconds]. Starts past it, so the first one
  /// always plays.
  double _sinceCrash = PitchCarsConfig.crashCooldownSeconds;

  /// Where an *off-car* aim is being drawn from, in world coordinates: the
  /// pull is the finger's displacement from here, added to [_preTurnPosition],
  /// which is what lets a drag that began nowhere near the car still aim it.
  ///
  /// Null means the finger came down on the car and the draw is measured from
  /// the car itself — so this doubles as "is there a pivot the player cannot
  /// see", which is exactly when the view draws a crosshair on it.
  Vector2? _dragOrigin;
  Vector2? _pull;
  bool _moving = false;
  Duration _sinceLaunch = Duration.zero;
  Duration _atRest = Duration.zero;

  /// Reset whenever the current car moves more than
  /// [PitchCarsConfig.stallDisplacement] away — feeds the stall watchdog.
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
        // Anywhere on the board starts an aim. A finger that lands *on* the
        // car pulls it directly, as before — the car follows the finger, which
        // is the gesture that reads as a slingshot. A finger that lands
        // anywhere else aims from where it landed, so the draw is the same
        // gesture measured from there.
        //
        // The car is regularly somewhere a finger cannot comfortably drag
        // from: pinned against the edge of a screen, or sitting on the seam
        // between two phones where half the draw would land on a neighbour's
        // glass. Requiring the gesture to *start* on the car made those
        // positions unplayable; nothing about aiming actually needs it to.
        final reach = scale.carRadius + scale.grabSlack;
        _dragOrigin = p.distanceTo(car.position) <= reach ? null : p.clone();
        _draggingPhoneId = touch.phoneId;
        _pull = _preTurnPosition.clone();
        _holdSound = _playOn(touch.phoneId, PitchCarsConfig.hold);

      case TouchPhase.move:
        if (_draggingPhoneId != touch.phoneId || _pull == null) return;
        // Aiming from the car makes the pull point the finger itself; aiming
        // from off it carries the same displacement back onto the car.
        final origin = _dragOrigin ?? _preTurnPosition;
        _pull = _clampPull(_preTurnPosition + (p - origin));
        _faceTheShot(car);

      case TouchPhase.up:
        if (_draggingPhoneId != touch.phoneId || _pull == null) return;
        _launch();
    }
  }

  // -- sound ------------------------------------------------------------------

  /// [cue] on [phoneId]'s phone, if somebody is sitting at it.
  SoundHandle? _playOn(String phoneId, SoundCue cue, {double volume = 1.0}) {
    final player = context.roster.byPhone(phoneId);
    if (player == null) return null;
    return context.audio.playOnPhone(player, cue, volume: volume);
  }

  /// A crash, on the phone under [x], [y] — or the nearest one, since an
  /// impact at the very edge of the glass can be a hair past it.
  void _crashAt(double x, double y) {
    if (_sinceCrash < PitchCarsConfig.crashCooldownSeconds) return;
    final phone = context.nearestPhone(x, y);
    if (phone == null) return;
    _sinceCrash = 0;
    _playOn(phone, PitchCarsConfig.crash, volume: PitchCarsConfig.crashVolume);
  }

  /// The last of a car's speed, braked away rather than coasted off.
  ///
  /// After the physics, so the brake has the last word on the tick: a car
  /// slower than [PitchCarsScale.brakeSpeed] loses a steady
  /// [PitchCarsScale.brakeDecel] a second — instead of the ever-smaller share
  /// damping takes — and one that reaches nothing is held there, spin and
  /// all. A car falling into the void is left to its fall.
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
    // Before the physics: that is where contacts, and so crashes, happen.
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
        // A car tumbling into the void is off the board and on a timer of its
        // own; its speed says nothing about whether the turn is over. The turn
        // waits for it to land (below), not for it to coast to a stop.
        if (_fallenFor.containsKey(id)) continue;
        final speed = carOf(id).linearVelocity.length;
        if (speed > maxSpeed) maxSpeed = speed;
      }
      // Stopped means stopped: [_brake] takes every car the last of the way to
      // exactly nothing, so there is no threshold to be under.
      _atRest = maxSpeed == 0 ? _atRest + elapsed : Duration.zero;

      // Angular damping should stop a car spinning-in-place well before
      // this, but this watchdog is the actual guarantee: force the turn to
      // end if the car hasn't translated in a while, regardless of why.
      final currentPos = carOf(currentTurn).position;
      if (_stallAnchor == null ||
          currentPos.distanceTo(_stallAnchor!) > scale.stallDisplacement) {
        _stallAnchor = currentPos.clone();
        _sinceStallAnchor = Duration.zero;
      } else {
        _sinceStallAnchor += elapsed;
      }

      // Never with a car still in the air: the next driver would be aiming
      // at a road with a car missing from it, and the one falling would land
      // back in the middle of their shot.
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
    // The road, kerbs and finish checkerboard. None of them draws in this
    // order — they carry no `ShapeProps.shape`, so `ShapeView` passes over
    // them and `PitchCarsView` paints them in the background, under the cars.
    yield* _trackEntities;
    yield* super.entities;
  }

  @override
  Map<String, Object?> get sharedState => {
    // The draw a full-strength shot takes, so the aim arrow reads power
    // against this table's own scale rather than a constant that is only
    // right for one size of board.
    'maxPull': scale.maxPull,
    'currentTurn': _roundOver ? null : currentTurn,
    'winner': _finishOrder.isEmpty ? null : _finishOrder.first,
    for (final id in _order) 'finished_$id': _finished.contains(id),
    // How far through its fall each car over the edge is, 0 to 1, so the view
    // can shrink and fade it into the void. Absent for a car on the road.
    // Lagged to line up with the positions the phones are drawing.
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
    // Pull point in world coords while aiming, null once released/idle —
    // the view draws the launch arrow from this to the current car.
    'pullX': _pull == null ? null : double.parse(_pull!.x.toStringAsFixed(3)),
    'pullY': _pull == null ? null : double.parse(_pull!.y.toStringAsFixed(3)),
    // The point an off-car drag is pivoting around, for the view to mark.
    // Null whenever the draw is measured from the car, which needs no mark:
    // the car is already standing on the spot.
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
    // Anything mid-fall is landed by the reset itself. Left behind, its id
    // would still read as falling on the new grid — skipped by the progress
    // update and by the rest check, and never put back.
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
