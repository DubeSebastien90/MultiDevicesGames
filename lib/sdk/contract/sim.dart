import '../model/coverage_map.dart';
import '../model/world_rect.dart';
import '../score/scoreboard.dart';
import 'entity.dart';

/// Touch phases, mirroring pointer events.
class TouchPhase {
  static const down = 'down';
  static const move = 'move';
  static const up = 'up';
}

/// A finger, already converted from that phone's local pixels to world space.
///
/// The sim does not know or care which screen it came from beyond [phoneId] —
/// which is exactly what makes a drag that crosses a seam ordinary.
class TouchEvent {
  const TouchEvent({
    required this.phoneId,
    required this.worldX,
    required this.worldY,
    required this.phase,
    this.pointerId = 0,
  });

  final String phoneId;
  final double worldX;
  final double worldY;
  final String phase;

  /// Distinguishes simultaneous fingers on the *same* phone.
  final int pointerId;
}

/// How a round ended.
class GameOutcome {
  const GameOutcome.won({this.summary}) : won = true;
  const GameOutcome.lost({this.summary}) : won = false;

  final bool won;

  /// A line for the results screen: '10 caught', 'the tower fell'.
  final String? summary;
}

/// One phone's slice of the world, named.
///
/// Also what the placement screen draws its diagram from, which is why it
/// carries a human label as well as a rectangle: the picture people are shown
/// has to be the layout the game actually chose, down to the gaps.
class PhoneSlice {
  const PhoneSlice(this.phoneId, this.screen, {this.label = ''});

  final String phoneId;

  /// Where that screen sits, turn included.
  final ScreenRect screen;

  /// Human name, for diagrams: 'Pixel 7'.
  final String label;

  /// Axis-aligned extent, for culling and framing.
  WorldRect get viewport => screen.bounds;

  /// Exact: is this world point on that screen?
  bool contains(double x, double y) => screen.contains(x, y);

  Map<String, dynamic> toJson() => {
    'phoneId': phoneId,
    'label': label,
    'screen': screen.toJson(),
  };

  static PhoneSlice fromJson(Map<String, dynamic> j) => PhoneSlice(
    j['phoneId'] as String,
    ScreenRect.fromJson(j['screen'] as Map<String, dynamic>),
    label: (j['label'] as String?) ?? '',
  );
}

/// Everything a simulation is handed when it is built.
class BoardContext {
  const BoardContext({
    required this.board,
    required this.coverage,
    required this.scores,
    required this.slices,
  });

  /// The playfield, in world units.
  final WorldRect board;

  /// Which parts of it are backed by a screen, for games that care.
  final CoverageMap coverage;

  /// The session scoreboard. Writable — this is the host.
  final Scoreboard scores;

  /// Every phone in the round, in board order.
  final List<PhoneSlice> slices;

  List<String> get phoneIds => [for (final s in slices) s.phoneId];

  /// Whose screen is this point on? Null in a gap between screens.
  ///
  /// The bridge between world coordinates and *people*, which is what
  /// per-phone scoring needs: the ball landed here, so whose was it?
  String? phoneAt(double x, double y) {
    for (final slice in slices) {
      if (slice.contains(x, y)) return slice.phoneId;
    }
    return null;
  }

  /// The phone whose screen is nearest to a point, for when a gap should not
  /// mean "nobody".
  String? nearestPhone(double x, double y) {
    String? best;
    var bestDistance = double.infinity;
    for (final slice in slices) {
      final v = slice.viewport;
      final dx = x < v.left ? v.left - x : (x > v.right ? x - v.right : 0.0);
      final dy = y < v.top ? v.top - y : (y > v.bottom ? y - v.bottom : 0.0);
      final d = dx * dx + dy * dy;
      if (d < bestDistance) {
        bestDistance = d;
        best = slice.phoneId;
      }
    }
    return best;
  }
}

/// The rules. Runs on the host, and only on the host.
///
/// [step] must be pure with respect to wall-clock time: no `DateTime.now()`, no
/// timers. The platform decides when time passes, which is what keeps the
/// timeline reproducible and the snapshots evenly spaced — and therefore what
/// keeps two screens agreeing at the seam.
abstract class GameSim {
  /// Advance by exactly [dt] seconds. Called at a fixed rate.
  void step(double dt);

  /// A finger, in world coordinates.
  void onTouch(TouchEvent touch);

  /// Everything drawable, this instant. Returning a new id makes it appear on
  /// every phone; ceasing to return one makes it vanish.
  Iterable<Entity> get entities;

  /// Small, slow-changing values every phone should see: phase, lives, whose
  /// turn it is. Broadcast when it changes, never interpolated. Per-phone
  /// points do not go here — that is the [Scoreboard].
  Map<String, Object?> get sharedState => const {};

  /// Non-null ends the round.
  GameOutcome? get outcome;

  /// Put the round back to its opening position.
  void reset();

  void dispose() {}
}
