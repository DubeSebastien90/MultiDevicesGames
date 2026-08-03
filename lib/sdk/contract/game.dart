import '../layout/board_plan.dart';
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
    this.minPhones = 1,
    this.maxPhones = 8,
  });

  /// Stable and wire-visible: every device resolves this to the same game.
  final String id;

  final String title;

  /// One line before the round: what you are about to do.
  final String tagline;

  /// How it ends, in the player's words: 'Hit the tower to win.'
  final String goal;

  /// The platform skips this game when the table does not fit.
  final int minPhones;
  final int maxPhones;

  bool fits(int phoneCount) =>
      phoneCount >= minPhones && phoneCount <= maxPhones;

  /// Why it does not fit, for the lobby to say out loud.
  String requirement() {
    if (minPhones == maxPhones) {
      return 'needs exactly $minPhones phones';
    }
    if (maxPhones >= 8) return 'needs $minPhones+ phones';
    return 'needs $minPhones–$maxPhones phones';
  }
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
