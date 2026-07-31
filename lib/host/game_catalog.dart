import '../game/mini_game.dart';
import '../model/arrangement.dart';
import '../model/coverage_map.dart';
import 'ball_bin_sim.dart';
import 'slingshot_sim.dart';

/// One minigame, as the host knows it before anything is built.
///
/// The important field is [arrangement]: a game declares the shape of board it
/// needs, and the placement flow reads it. That is what makes "next game" mean
/// "everyone pick up your phone and put it somewhere else".
class MiniGameDef {
  const MiniGameDef({
    required this.id,
    required this.title,
    required this.tagline,
    required this.goal,
    required this.arrangement,
    required this.build,
  });

  /// Stable wire id. Clients use it to label screens, never to build anything.
  final String id;

  final String title;

  /// One line on the arrangement screen: what you are about to do.
  final String tagline;

  /// How the round ends, in the player's words.
  final String goal;

  final Arrangement arrangement;

  /// Builds the authoritative world once the board is known.
  final MiniGameSim Function(CoverageMap coverage) build;
}

MiniGameSim _buildSlingshot(CoverageMap c) => SlingshotSim(coverage: c);
MiniGameSim _buildBallBin(CoverageMap c) => BallBinSim(coverage: c);

/// Every minigame, and the order they are played in.
///
/// A fixed playlist that wraps: win one and the next begins, forever. The
/// arrangement alternates on purpose — rearranging the phones between rounds is
/// part of the game rather than an interruption to it.
class GameCatalog {
  const GameCatalog._();

  static const slingshot = MiniGameDef(
    id: 'slingshot',
    title: 'Slingshot',
    tagline: 'Pull the bird back and knock the tower down.',
    goal: 'Hit the tower to win.',
    arrangement: Arrangement.strip,
    build: _buildSlingshot,
  );

  static const ballBin = MiniGameDef(
    id: 'ballbin',
    title: 'Ball Bin',
    tagline: 'Balls fall down the screens. Slide the bin and catch them.',
    goal: 'Catch 10 balls to win.',
    arrangement: Arrangement.stack,
    build: _buildBallBin,
  );

  static const playlist = <MiniGameDef>[slingshot, ballBin];

  /// The playlist wraps, so an index is always valid.
  static MiniGameDef at(int index) =>
      playlist[index % playlist.length];
}
