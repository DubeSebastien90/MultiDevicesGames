import '../games/arena/arena_game.dart';
import '../games/ball_bin/ball_bin_game.dart';
import '../games/dodgeball/dodgeball_game.dart';
import '../games/flood/flood_game.dart';
import '../games/flood_closing/flood_closing_game.dart';
import '../games/guacamole/guacamole_game.dart';
import '../games/hot_potato/hot_potato_game.dart';
import '../games/pitch_cars/pitch_cars_game.dart';
import '../games/random_path/random_path_game.dart';
import '../games/reaction/reaction_game.dart';
import '../games/slingshot/slingshot_game.dart';
import 'contract/game.dart';

/// Every game, and the order they are played in.
///
/// **This is the only file in `sdk/` that knows `games/` exists.** Keeping it to
/// one import list is what makes the boundary real: everything else in the SDK
/// works against [MultiscreenGame] and has never heard of a slingshot. It is
/// also the line a package extraction would cut along, if this ever becomes a
/// published SDK rather than a folder convention.
///
/// Registering a game is one import and one list entry.
class GameCatalog {
  const GameCatalog._();

  static const playlist = <MultiscreenGame>[
    SlingshotGame(),
    BallBinGame(),
    HotPotatoGame(),
    FloodGame(),
    FloodClosingGame(),
    ArenaGame(),
    DodgeballGame(),
    GuacamoleGame(),
    PitchCarsGame(),
    ReactionGame(),
    RandomPathGame(),
  ];

  /// Bumped when the contract changes shape in a way that would make two builds
  /// disagree about the wire format.
  static const contractVersion = 1;

  /// Identifies this build's game list, so a phone running a different version
  /// is turned away with a clear message instead of a blank screen.
  ///
  /// Games run on every device now; a client that lacks a game cannot render
  /// it. This is the ordinary consequence of games shipping in the binary, and
  /// it bites the first time two people install a week apart.
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

  static bool anyPlayable(int phoneCount) =>
      playlist.any((g) => g.manifest.fits(phoneCount));

  /// The game at [index] if it fits the table, otherwise the next one along
  /// that does. Null once the list runs out.
  ///
  /// **Does not wrap.** The playlist is played through once and then everyone
  /// is back in the lobby, which is what makes it an evening rather than a
  /// treadmill nobody can get off. Null therefore means two different things
  /// worth telling apart: from index 0 it means nothing fits this table at all,
  /// and from further in it means the list is finished.
  static MultiscreenGame? playableFrom(int index, int phoneCount) {
    final at = playableIndexFrom(index, phoneCount);
    return at == null ? null : playlist[at];
  }

  /// The index of the first playable game at or after [index], for advancing
  /// the playlist without losing your place. Null once nothing is left.
  static int? playableIndexFrom(int index, int phoneCount) {
    for (var at = index; at < playlist.length; at++) {
      if (playlist[at].manifest.fits(phoneCount)) return at;
    }
    return null;
  }

  /// What to tell the host when nothing fits.
  ///
  /// Ordered by how close each game is to playable, so a table of two is told
  /// about the game needing three before the one needing eight. That is the
  /// difference between "here is a wall of requirements" and "add one phone".
  static String requirementSummary() {
    final byReach = List.of(playlist)
      ..sort((a, b) =>
          a.manifest.smallestTable.compareTo(b.manifest.smallestTable));
    return byReach
        .map((g) => '${g.manifest.title} ${g.manifest.requirement()}')
        .join('; ');
  }

  /// Every count that would let *something* be played, for the lobby to
  /// suggest. Empty only if no game is playable at any size.
  static List<int> playableTableSizes({int ceiling = 8}) => [
    for (var n = 1; n <= ceiling; n++)
      if (anyPlayable(n)) n,
  ];
}
