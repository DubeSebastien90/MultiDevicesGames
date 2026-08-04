import '../model/coverage_map.dart';
import '../model/player_color.dart';
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

/// What kind of ending a round had. Named rather than inferred from which
/// field happens to be null — a draw is a decision a game makes, not an absence
/// of information.
enum OutcomeKind {
  /// The table succeeded or failed together. Ball Bin caught its ten.
  shared,

  /// Some phones won and the rest did not.
  contest,

  /// A contest nobody won.
  draw,

  /// No winning at all — every phone gets its own line. A score attack.
  personal,
}

/// How a round ended, and what each phone should be told about it.
///
/// Four shapes, because "who won" is not the same question for every game:
///
/// ```dart
/// GameOutcome.won(summary: 'the tower fell')            // the table did it
/// GameOutcome.contest(winners: {'p1'}, summary: '…')    // p1 won, others did not
/// GameOutcome.draw(summary: 'dead level')               // nobody won
/// GameOutcome.perPhone({'p1': 'You made 320 points'})   // no winning, just facts
/// ```
///
/// [lines] can ride along with any of them, so a contest can say **You win!**
/// *and* "320 points" underneath. The platform owns the headline; a game owns
/// the facts under it.
///
/// Whatever you build here, build it **once and keep it**: `outcome` is polled
/// several times a tick, and constructing a fresh map each time is work nobody
/// asked for.
class GameOutcome {
  const GameOutcome.won({this.summary, this.lines})
      : kind = OutcomeKind.shared,
        won = true,
        winners = null;

  const GameOutcome.lost({this.summary, this.lines})
      : kind = OutcomeKind.shared,
        won = false,
        winners = null;

  /// Some phones won. Everyone not named is told they lost, so name every
  /// winner — including all of them, if a whole team won together.
  const GameOutcome.contest({
    required Set<String> this.winners,
    this.summary,
    this.lines,
  })  : kind = OutcomeKind.contest,
        won = true;

  /// Nobody won, and that is the result rather than a missing one.
  const GameOutcome.draw({this.summary, this.lines})
      : kind = OutcomeKind.draw,
        won = false,
        winners = null;

  /// A line each, keyed by `phoneId`. Phones you leave out fall back to
  /// [summary], so a game that only has something to say about some of them
  /// still reads properly on the rest.
  const GameOutcome.perPhone(Map<String, String> this.lines, {this.summary})
      : kind = OutcomeKind.personal,
        won = true,
        winners = null;

  final OutcomeKind kind;

  /// Only meaningful for [OutcomeKind.shared]: did the table manage it?
  final bool won;

  /// Who won. Non-null exactly when [kind] is [OutcomeKind.contest].
  final Set<String>? winners;

  /// A line for one phone in particular: 'You made 320 points'.
  final Map<String, String>? lines;

  /// A line for the results screen, the same on every phone: '10 caught',
  /// 'the tower fell'.
  final String? summary;
}

/// One phone's slice of the world, named.
///
/// Also what the placement screen draws its diagram from, which is why it
/// carries a human label as well as a rectangle: the picture people are shown
/// has to be the layout the game actually chose, down to the gaps.
class PhoneSlice {
  const PhoneSlice(
    this.phoneId,
    this.screen, {
    this.label = '',
    this.color,
  });

  final String phoneId;

  /// Where that screen sits, turn included.
  final ScreenRect screen;

  /// Human name, for diagrams: 'Pixel 7'.
  final String label;

  /// Whose screen this is, as a colour. Travels with the slice so both ends
  /// agree: the sim deals moles by it, and every phone draws the same owner in
  /// the same shade without asking anyone.
  final PlayerColor? color;

  /// Axis-aligned extent, for culling and framing.
  WorldRect get viewport => screen.bounds;

  /// Exact: is this world point on that screen?
  bool contains(double x, double y) => screen.contains(x, y);

  Map<String, dynamic> toJson() => {
    'phoneId': phoneId,
    'label': label,
    if (color != null) 'color': color!.id,
    'screen': screen.toJson(),
  };

  static PhoneSlice fromJson(Map<String, dynamic> j) => PhoneSlice(
    j['phoneId'] as String,
    ScreenRect.fromJson(j['screen'] as Map<String, dynamic>),
    label: (j['label'] as String?) ?? '',
    color: PlayerPalette.byId(j['color'] as String?),
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

  /// Everyone playing, as a colour each, in board order.
  ///
  /// A game that scores by colour builds its player list from this and never
  /// touches [phoneIds]: the two are the same length only when every phone has
  /// been seated, and the difference is exactly the case that would silently
  /// deal points to nobody.
  List<PlayerColor> get players => [
    for (final s in slices)
      if (s.color != null) s.color!,
  ];

  /// Which phone wears this colour. The inverse of [colorOf], and the bridge
  /// from "this thing belongs to Green" back to a row of the [Scoreboard].
  String? phoneOfColor(PlayerColor color) {
    for (final s in slices) {
      if (s.color?.id == color.id) return s.phoneId;
    }
    return null;
  }

  PlayerColor? colorOf(String phoneId) {
    for (final s in slices) {
      if (s.phoneId == phoneId) return s.color;
    }
    return null;
  }

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
