import 'package:forge2d/forge2d.dart';

import 'rally_config.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/physics/forge2d_game_sim.dart';
import '../../sdk/render/shape_view.dart';

/// A single ball bounced back and forth along a wide, short lane. A tap that
/// lands near the ball sends it back the way it came, a little faster and
/// angled by where on the ball the tap landed; miss it and it rolls clean off
/// your own end, scoring the other side a point.
///
/// Two teams read off where their phones physically ended up, the same way
/// Push of War's do — but where that game accumulates one shove at a time
/// toward a single crossing that ends the round, this one resets to the
/// middle after every point and plays to a target score, the way a real
/// rally does. The tap itself is reach-gated like Beach Ball's bump, not
/// position-blind like Push of War's push: it matters *where* near the ball
/// you tap, because that is what aims the return.
class RallySim extends Forge2DGameSim {
  RallySim(super.context) : super(gravity: Vector2.zero()) {
    final teams = _splitTeams(context);
    _teamA = teams.teamA;
    _teamB = teams.teamB;
    _seated = {..._teamA, ..._teamB};

    // Only the long edges of the lane bounce the ball back into play; the
    // short ends stay open so it can roll clean off the board — that is how
    // a point is conceded.
    addBoundaryWalls(
      top: true,
      bottom: true,
      left: false,
      right: false,
      restitution: RallyConfig.wallRestitution,
    );
    _addBall();
    _serve();
  }

  static const _ballId = 'ball';

  late final Set<String> _teamA;
  late final Set<String> _teamB;
  late final Set<String> _seated;

  int _pointsA = 0;
  int _pointsB = 0;
  int _serveCount = 0;
  double _elapsed = 0;
  double? _lastHitAt;
  GameOutcome? _outcome;

  static ({Set<String> teamA, Set<String> teamB}) _splitTeams(
    BoardContext context,
  ) {
    final sorted = List.of(context.slices)
      ..sort((a, b) => a.viewport.centerX.compareTo(b.viewport.centerX));
    final half = sorted.length ~/ 2;
    return (
      teamA: {for (final s in sorted.take(half)) s.phoneId},
      teamB: {for (final s in sorted.skip(half)) s.phoneId},
    );
  }

  void _addBall() {
    addBody(
      _ballId,
      'ball',
      BodyDef(
        type: BodyType.dynamic,
        position: Vector2(board.centerX, board.centerY),
        bullet: true,
      ),
      props: {
        ShapeProps.shape: ShapeKind.circle,
        ShapeProps.radius: RallyConfig.ballRadius,
        ShapeProps.color: RallyConfig.colorBall,
        ShapeProps.spin: true,
      },
    ).createFixture(
      FixtureDef(
        CircleShape(radius: RallyConfig.ballRadius),
        density: RallyConfig.ballDensity,
        friction: 0.0,
        restitution: RallyConfig.wallRestitution,
      ),
    );
  }

  /// Puts the ball back at the centre of the lane with a fresh serve.
  /// Alternates direction every point — deterministic rather than random, so
  /// a round replays identically from the same taps.
  void _serve() {
    final ball = bodyOf(_ballId)!;
    ball
      ..setTransform(Vector2(board.centerX, board.centerY), 0)
      ..angularVelocity = 0
      ..setAwake(true);
    final dir = _serveCount.isEven ? 1.0 : -1.0;
    final vy =
        _serveCount.isEven ? RallyConfig.serveSpeedY : -RallyConfig.serveSpeedY;
    ball.linearVelocity = Vector2(dir * RallyConfig.serveSpeedX, vy);
  }

  // ----------------------------------------------------------------- input

  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (_outcome != null) return;
    if (!_seated.contains(touch.phoneId)) return;

    if (_lastHitAt != null &&
        _elapsed - _lastHitAt! < RallyConfig.hitCooldownSeconds) {
      return;
    }

    final ball = bodyOf(_ballId)!;
    final dx = touch.worldX - ball.position.x;
    final dy = touch.worldY - ball.position.y;
    final reach = RallyConfig.ballRadius + RallyConfig.hitReach;
    if (dx * dx + dy * dy > reach * reach) return;

    _lastHitAt = _elapsed;
    final v = ball.linearVelocity;
    final speed = (v.x.abs() + RallyConfig.hitSpeedBoost).clamp(
      0.0,
      RallyConfig.maxBallSpeedX,
    );
    // Reverse whichever way it was travelling — a return, not a shove.
    final newVx = v.x <= 0 ? speed : -speed;
    final newVy = ((ball.position.y - touch.worldY) * RallyConfig.deflectFactor)
        .clamp(-RallyConfig.maxBallSpeedY, RallyConfig.maxBallSpeedY);
    ball.linearVelocity = Vector2(newVx, newVy);
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    if (_outcome != null) return;
    _elapsed += dt;
    super.step(dt);
    _clampSpeed();
    _checkGoal();
    if (_outcome == null && _elapsed >= RallyConfig.maxRoundSeconds) {
      _finishByTime();
    }
  }

  void _clampSpeed() {
    final ball = bodyOf(_ballId)!;
    final v = ball.linearVelocity;
    final vx = v.x.clamp(-RallyConfig.maxBallSpeedX, RallyConfig.maxBallSpeedX);
    final vy = v.y.clamp(-RallyConfig.maxBallSpeedY, RallyConfig.maxBallSpeedY);
    if (vx != v.x || vy != v.y) ball.linearVelocity = Vector2(vx, vy);
  }

  void _checkGoal() {
    if (_outcome != null) return;
    final x = bodyOf(_ballId)!.position.x;
    if (x + RallyConfig.ballRadius < board.left) {
      // The left side's own baseline gave way — the right side scores.
      _awardPoint(_teamB, isTeamA: false);
    } else if (x - RallyConfig.ballRadius > board.right) {
      _awardPoint(_teamA, isTeamA: true);
    }
  }

  void _awardPoint(Set<String> scoringTeam, {required bool isTeamA}) {
    if (isTeamA) {
      _pointsA++;
    } else {
      _pointsB++;
    }
    for (final id in scoringTeam) {
      scores.award(id, RallyConfig.pointValue);
    }
    _serveCount++;

    if (_pointsA >= RallyConfig.targetPoints ||
        _pointsB >= RallyConfig.targetPoints) {
      _finish(
        winners: scoringTeam,
        summary: isTeamA
            ? 'the left side took the rally $_pointsA–$_pointsB'
            : 'the right side took the rally $_pointsB–$_pointsA',
      );
    } else {
      _serve();
    }
  }

  void _finishByTime() {
    if (_pointsA == _pointsB) {
      _outcome = GameOutcome.draw(summary: 'time ran out, tied at $_pointsA');
      return;
    }
    final teamAWins = _pointsA > _pointsB;
    _finish(
      winners: teamAWins ? _teamA : _teamB,
      summary: 'time ran out ${teamAWins ? _pointsA : _pointsB}–'
          '${teamAWins ? _pointsB : _pointsA}',
    );
  }

  void _finish({required Set<String> winners, required String summary}) {
    _outcome = GameOutcome.contest(winners: winners, summary: summary);
  }

  @override
  Map<String, Object?> get sharedState => {
    'pointsA': _pointsA,
    'pointsB': _pointsB,
    'targetPoints': RallyConfig.targetPoints,
  };

  @override
  GameOutcome? get outcome => _outcome;

  @override
  void reset() {
    _pointsA = 0;
    _pointsB = 0;
    _serveCount = 0;
    _elapsed = 0;
    _lastHitAt = null;
    _outcome = null;
    _serve();
  }
}
