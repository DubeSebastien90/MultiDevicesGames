import '../audio/game_audio.dart';
import '../model/coverage_map.dart';
import '../model/player.dart';
import '../model/player_color.dart';
import '../model/world_rect.dart';
import '../score/scoreboard.dart';
import 'entity.dart';

class TouchPhase {
  static const down = 'down';
  static const move = 'move';
  static const up = 'up';
}

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

  final int pointerId;
}

enum OutcomeKind { shared, contest, draw, personal }

class GameOutcome {
  const GameOutcome.won({this.summary, this.lines})
    : kind = OutcomeKind.shared,
      won = true,
      winners = null;

  const GameOutcome.lost({this.summary, this.lines})
    : kind = OutcomeKind.shared,
      won = false,
      winners = null;

  const GameOutcome.contest({
    required Set<String> this.winners,
    this.summary,
    this.lines,
  }) : kind = OutcomeKind.contest,
       won = true;

  const GameOutcome.draw({this.summary, this.lines})
    : kind = OutcomeKind.draw,
      won = false,
      winners = null;

  const GameOutcome.perPhone(Map<String, String> this.lines, {this.summary})
    : kind = OutcomeKind.personal,
      won = true,
      winners = null;

  final OutcomeKind kind;

  final bool won;

  final Set<String>? winners;

  final Map<String, String>? lines;

  final String? summary;
}

class PhoneSlice {
  const PhoneSlice(this.phoneId, this.screen, {this.label = '', this.color});

  final String phoneId;

  final ScreenRect screen;

  final String label;

  final PlayerColor? color;

  WorldRect get viewport => screen.bounds;

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

class BoardContext {
  const BoardContext({
    required this.board,
    required this.coverage,
    required this.scores,
    required this.slices,
    this.roster = Roster.empty,
    this.audio = const SilentGameAudio(),
  });

  final WorldRect board;

  final CoverageMap coverage;

  final Scoreboard scores;

  final List<PhoneSlice> slices;

  final Roster roster;

  final GameAudio audio;

  List<String> get phoneIds => [for (final s in slices) s.phoneId];

  List<PlayerColor> get players => [
    for (final s in slices)
      if (s.color != null) s.color!,
  ];

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

  String? phoneAt(double x, double y) {
    for (final slice in slices) {
      if (slice.contains(x, y)) return slice.phoneId;
    }
    return null;
  }

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

abstract class PlayerPresence {
  void onPlayerLeft(String phoneId);

  void onPlayerReturned(String phoneId);
}

abstract class GameSim {
  void step(double dt);

  void onTouch(TouchEvent touch);

  Iterable<Entity> get entities;

  Map<String, Object?> get sharedState => const {};

  GameOutcome? get outcome;

  void reset();

  void dispose() {}
}
