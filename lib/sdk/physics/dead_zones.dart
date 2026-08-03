import 'package:forge2d/forge2d.dart';

import '../model/coverage_map.dart';

/// What a game does about the space between screens.
///
/// The gap is physically real: the world is continuous and the simulation runs
/// straight through it. What varies is whether that is a feature. These are
/// helpers, not rules — a game that wants a portal in the seam writes it
/// against [CoverageMap] directly.
class DeadZones {
  const DeadZones._();

  /// Do nothing, which is almost always right. An object crosses the gap
  /// invisibly and reappears exactly where momentum says it should. That is
  /// the seam trick, and both shipped games rely on it.
  static void ignore() {}

  /// Fill every seam with a static body, for a game where a piece must never
  /// be lost in a gap.
  ///
  /// Note what this costs: the board stops being one continuous space, and an
  /// object that would have sailed across now stops dead at a line the player
  /// cannot see. Worth it for a puzzle, wrong for anything with momentum.
  static List<Body> wall(
    World world,
    CoverageMap coverage, {
    double friction = 0.4,
    double restitution = 0.1,
  }) {
    final bodies = <Body>[];
    for (final (i, seam) in coverage.seamRects().indexed) {
      final body = world.createBody(
        BodyDef(position: Vector2(seam.centerX, seam.centerY)),
      )..userData = 'seamWall$i';
      body.createFixture(
        FixtureDef(
          PolygonShape()..setAsBoxXY(seam.width / 2, seam.height / 2),
          friction: friction,
          restitution: restitution,
        ),
      );
      bodies.add(body);
    }
    return bodies;
  }

  /// True when a point is in a gap rather than on a screen — for a game that
  /// wants to retire whatever settles there, or score it.
  static bool isLost(CoverageMap coverage, double x, double y) =>
      coverage.board.contains(x, y) && !coverage.isCovered(x, y);
}
