import '../layout/board_plan.dart';
import 'player_count.dart';
import '../layout/phone_spec.dart';
import 'sim.dart';
import 'view.dart';

/// Who a game is, and what table it needs.
class GameManifest {
  const GameManifest({
    required this.id,
    required this.title,
    required this.tagline,
    required this.goal,
    this.players = const PlayerCount.range(min: 1),
    this.supportsIpad = false,
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
