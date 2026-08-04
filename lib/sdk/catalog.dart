import '../games/ball_bin/ball_bin_game.dart';
import '../games/hot_potato/hot_potato_game.dart';
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
  /// that does. Null when nothing fits.
  ///
  /// The playlist wraps, so this only returns null when *no* game can be played
  /// at this phone count — which the lobby says out loud rather than offering a
  /// Play button that fails.
  static MultiscreenGame? playableFrom(int index, int phoneCount) {
    for (var i = 0; i < playlist.length; i++) {
      final game = playlist[(index + i) % playlist.length];
      if (game.manifest.fits(phoneCount)) return game;
    }
    return null;
  }

  /// The index of the first playable game at or after [index], for advancing
  /// the playlist without losing your place.
  static int? playableIndexFrom(int index, int phoneCount) {
    for (var i = 0; i < playlist.length; i++) {
      final at = (index + i) % playlist.length;
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
