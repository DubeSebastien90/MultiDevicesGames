import '../layout/board_plan.dart';
import 'player_count.dart';
import '../layout/phone_spec.dart';
import 'sim.dart';
import 'view.dart';

/// Whether a game is free for everyone or requires Premium to be unlocked.
///
/// Lives on the manifest, next to the id and title, rather than in a separate
/// list elsewhere: a game's tier is a fact about the game, the same kind of
/// fact as its title or its player count, and belongs where those are
/// declared so nobody has to cross-reference two files to know what a game
/// costs.
enum GameTier {
  /// Playable, and pickable into the run, by anyone.
  free,

  /// Requires Premium to be picked into the run or played.
  premium,
}

/// Who a game is, and what table it needs.
class GameManifest {
  const GameManifest({
    required this.id,
    required this.title,
    required this.tagline,
    required this.goal,
    this.players = const PlayerCount.range(min: 1),
    this.supportsIpad = false,
    this.tier = GameTier.free,
    this.skipNameDropOptimizer = false,
  });

  /// Stable and wire-visible: every device resolves this to the same game.
  final String id;

  final String title;

  /// One line before the round: what you are about to do.
  final String tagline;

  /// How it ends, in the player's words: 'Hit the tower to win.'
  final String goal;

  /// How many phones this can be played with. The platform skips the game when
  /// the table does not fit.
  final PlayerCount players;

  /// Whether the game is happy on a tablet.
  ///
  /// **Nothing reads this yet.** It is declared now so manifests do not have to
  /// change later, but the lobby does not filter on it: a game leaving this
  /// false will still be offered to a table with an iPad in it.
  ///
  /// Defaults to false so support is something a game claims deliberately,
  /// having been tried on one, rather than something it inherits by silence.
  ///
  /// Wiring it up means first deciding what counts as a tablet, which is a
  /// judgement about screen size rather than platform — an iPad mini and a
  /// large phone are not far apart, and Android tablets exist. Most likely a
  /// threshold on [PhoneSpec.diagonalMm] rather than a platform check.
  final bool supportsIpad;

  /// Free forever, or behind Premium. Defaults to [GameTier.free] so a game
  /// that never mentions it is free — the same "declared deliberately" shape
  /// as [supportsIpad].
  final GameTier tier;

  bool get isPremium => tier == GameTier.premium;

  /// Dev-only escape hatch: skip [NameDropOptimizer] when planting this game's
  /// board, so a plan that deliberately puts two phones top to top stays that
  /// way instead of being turned safe. Not for real games.
  final bool skipNameDropOptimizer;

  bool fits(int phoneCount) => players.fits(phoneCount);

  /// Why it does not fit, for the lobby to say out loud.
  String requirement() => players.describe();

  /// The fewest phones this needs — for ordering a catalogue, and for telling a
  /// short-handed table which game is closest to playable.
  int get smallestTable => players.smallest;
}

/// A game on this platform.
///
/// Four members: who am I, where do the phones go, what are the rules, and what
/// does it look like. The platform owns discovery, the lobby, transport, the
/// shared timeline and the camera; a game owns everything else.
abstract class MultiscreenGame {
  GameManifest get manifest;

  /// Where the phones go. Runs the moment the game is chosen — before anything
  /// is broadcast — so a bad plan fails on the host rather than sending
  /// everyone to rearrange a table for a round that cannot start.
  ///
  /// The plan leads and people follow it: the placement screen tells each phone
  /// where to go, so this describes the table about to be built, not one that
  /// already exists.
  BoardPlan planBoard(LobbyInfo lobby);

  /// The authoritative world. Host only.
  GameSim createSim(BoardContext context);

  /// The renderer. Every phone, including the host's.
  GameView createView(ViewContext context);
}
