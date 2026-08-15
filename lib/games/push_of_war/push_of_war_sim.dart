import 'package:forge2d/forge2d.dart';

import 'push_of_war_config.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/physics/forge2d_game_sim.dart';
import '../../sdk/render/shape_view.dart';

/// A ball at the middle of a long, narrow board. Tap your side to shove it
/// toward the other team's end; push it past their line and your team wins.
///
/// Zero gravity, one body, two teams read off where their phones physically
/// ended up — the tug-of-war Flood plays with a float, played instead with
/// real physics on the row layout, which nothing else here does.
class PushOfWarSim extends Forge2DGameSim {
  PushOfWarSim(super.context) : super(gravity: Vector2.zero()) {
    final teams = _splitTeams(context);
    _isTeamA = teams;
    _teamA = {for (final e in teams.entries) if (e.value) e.key};
    _teamB = {for (final e in teams.entries) if (!e.value) e.key};

    final b = board;
    _leftGoalX = b.left + b.width * PushOfWarConfig.goalMarginFraction;
    _rightGoalX = b.right - b.width * PushOfWarConfig.goalMarginFraction;

    // Only the top and bottom keep the ball on the lane. The left and right
    // ends stay open — crossing one of them is how a team wins.
    addBoundaryWalls(top: true, bottom: true, left: false, right: false);
    _addBall();
  }

  static const _ballId = 'ball';

  /// phoneId -> true for the team occupying the left half of the board, read
  /// once from where the phones actually landed rather than from
  /// [planBoard]'s own sort — a phone in the left half is team A because that
  /// is the territory it is physically sitting in.
  late final Map<String, bool> _isTeamA;
  late final Set<String> _teamA;
  late final Set<String> _teamB;

  late final double _leftGoalX;
  late final double _rightGoalX;

  final _lastTapAt = <String, double>{};
  double _elapsed = 0;
  bool _scored = false;
  GameOutcome? _outcome;

  static Map<String, bool> _splitTeams(BoardContext context) {
    final sorted = List.of(context.slices)
      ..sort((a, b) => a.viewport.centerX.compareTo(b.viewport.centerX));
    final half = sorted.length ~/ 2;
    return {
      for (var i = 0; i < sorted.length; i++) sorted[i].phoneId: i < half,
    };
  }

  void _addBall() {
    final b = board;
    addBody(
      _ballId,
      'ball',
      BodyDef(
        type: BodyType.dynamic,
        position: Vector2(b.centerX, b.centerY),
        linearDamping: PushOfWarConfig.ballLinearDamping,
        bullet: true,
      ),
      props: {
        ShapeProps.shape: ShapeKind.circle,
        ShapeProps.radius: PushOfWarConfig.ballRadius,
        ShapeProps.color: PushOfWarConfig.colorBall,
        ShapeProps.spin: true,
      },
    ).createFixture(
      FixtureDef(
        CircleShape(radius: PushOfWarConfig.ballRadius),
        density: PushOfWarConfig.ballDensity,
        friction: 0.1,
        restitution: PushOfWarConfig.ballRestitution,
      ),
    );
  }

  // ----------------------------------------------------------------- input

  /// Every touch-down on any phone is one shove for that phone's team.
  ///
  /// Deliberately position-blind, the same way Flood reads a tap: the whole
  /// screen is the button, so mashing does not also require aiming.
  @override
  void onTouch(TouchEvent touch) {
    if (touch.phase != TouchPhase.down) return;
    if (_outcome != null) return;

    final isTeamA = _isTeamA[touch.phoneId];
    if (isTeamA == null) return;

    final last = _lastTapAt[touch.phoneId];
    if (last != null &&
        _elapsed - last < PushOfWarConfig.minTapIntervalSeconds) {
      return;
    }
    _lastTapAt[touch.phoneId] = _elapsed;

    // Team A sits on the left and shoves right, toward team B's line.
    final direction = isTeamA ? 1.0 : -1.0;
    bodyOf(_ballId)!.applyLinearImpulse(
      Vector2(direction * PushOfWarConfig.pushImpulse, 0),
    );
  }

  // ------------------------------------------------------------------ step

  @override
  void step(double dt) {
    if (_outcome != null) return;

    _elapsed += dt;
    super.step(dt);
    _checkGoal();

    if (_outcome == null && _elapsed >= PushOfWarConfig.maxRoundSeconds) {
      _outcome = GameOutcome.draw(summary: 'time ran out at the middle line');
    }
  }

  void _checkGoal() {
    if (_scored) return;
    final x = bodyOf(_ballId)!.position.x;
    if (x - PushOfWarConfig.ballRadius <= _leftGoalX) {
      _finish(teamAWins: false);
    } else if (x + PushOfWarConfig.ballRadius >= _rightGoalX) {
      _finish(teamAWins: true);
    }
  }

  /// Award and latch, once — polled several times a tick, so this must build
  /// the same [GameOutcome] every time rather than a fresh one.
  void _finish({required bool teamAWins}) {
    _scored = true;
    final winners = teamAWins ? _teamA : _teamB;
    for (final id in winners) {
      scores.award(id, PushOfWarConfig.winPoints);
    }
    _outcome = GameOutcome.contest(
      winners: winners,
      summary: teamAWins
          ? 'the left side pushed it all the way across'
          : 'the right side pushed it all the way across',
    );
  }

  @override
  GameOutcome? get outcome => _outcome;

  @override
  void reset() {
    _lastTapAt.clear();
    _elapsed = 0;
    _scored = false;
    _outcome = null;
    final b = board;
    bodyOf(_ballId)!
      ..setTransform(Vector2(b.centerX, b.centerY), 0)
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..setAwake(true);
  }
}
