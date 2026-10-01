import '../games/arena/arena_game.dart';
import '../games/cops_robbers/cops_robbers_game.dart';
import '../games/dodgeball/dodgeball_game.dart';
import '../games/flood/flood_game.dart';
import '../games/guacamole/guacamole_game.dart';
import '../games/hot_potato/hot_potato_game.dart';
import '../games/paint_war/paint_war_game.dart';
import '../games/pitch_cars/pitch_cars_game.dart';
import '../games/hungry_hippos/hungry_hippos_game.dart';
import '../games/subway_skater/subway_skater_game.dart';
import 'contract/game.dart';

class GameCatalog {
  const GameCatalog._();

  static const playlist = <MultiscreenGame>[
    HotPotatoGame(),
    FloodGame(),
    ArenaGame(),
    PitchCarsGame(),
    SubwaySkaterGame(),
    PaintWarGame(),
    GuacamoleGame(),
    HungryHipposGame(),
    DodgeballGame(),
    CopsRobbersGame(),
  ];

  static const contractVersion = 1;

  static String get fingerprint {
    final ids = [for (final g in playlist) g.manifest.id]..sort();
    return 'v$contractVersion:${ids.join(',')}';
  }

  static MultiscreenGame? byId(String id) {
    for (final game in playlist) {
      if (game.manifest.id == id) return game;
    }
    return null;
  }

  static Iterable<MultiscreenGame> _considered(Set<String> skipping) =>
      skipping.isEmpty
      ? playlist
      : playlist.where((g) => !skipping.contains(g.manifest.id));

  static bool anyPlayable(int phoneCount, {Set<String> skipping = const {}}) =>
      _considered(skipping).any((g) => g.manifest.fits(phoneCount));

  static MultiscreenGame? playableFrom(
    int index,
    int phoneCount, {
    Set<String> skipping = const {},
    List<MultiscreenGame> order = playlist,
  }) {
    final at = playableIndexFrom(
      index,
      phoneCount,
      skipping: skipping,
      order: order,
    );
    return at == null ? null : order[at];
  }

  static int? playableIndexFrom(
    int index,
    int phoneCount, {
    Set<String> skipping = const {},
    List<MultiscreenGame> order = playlist,
  }) {
    for (var at = index; at < order.length; at++) {
      final game = order[at];
      if (skipping.contains(game.manifest.id)) continue;
      if (game.manifest.fits(phoneCount)) return at;
    }
    return null;
  }

  static String requirementSummary({Set<String> skipping = const {}}) {
    final byReach = List.of(_considered(skipping))
      ..sort(
        (a, b) => a.manifest.smallestTable.compareTo(b.manifest.smallestTable),
      );
    return byReach
        .map((g) => '${g.manifest.title} ${g.manifest.requirement()}')
        .join('; ');
  }

  static List<int> playableTableSizes({
    int ceiling = 8,
    Set<String> skipping = const {},
  }) => [
    for (var n = 1; n <= ceiling; n++)
      if (anyPlayable(n, skipping: skipping)) n,
  ];
}
