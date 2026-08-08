import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import '../../sdk/model/player_color.dart';
import 'reaction_sim.dart';
import 'reaction_view.dart';

/// One screen lights up at a time. Tap yours the instant it does.
///
/// The simplest game here, and the one that leans on the platform least: no
/// physics, no entities, nothing crossing the seam. What it does need is the
/// part that is genuinely hard — one clock, one chooser — so that thirty
/// seconds of turns are dealt out evenly and every reaction is measured against
/// the same instant.
class ReactionGame implements MultiscreenGame {
  const ReactionGame();

  @override
  GameManifest get manifest => GameManifest(
    id: 'reaction',
    title: 'Reaction Time',
    tagline: 'Screens flash one at a time. Tap yours the moment it does.',
    goal: 'The fastest average when the thirty seconds are up.',
    // Two is a race; alone there is nobody to be faster than. The ceiling is
    // the palette, because a turn is announced by a player's colour and two
    // people sharing one would not know whose turn it was.
    players: PlayerCount.range(min: 2, max: PlayerPalette.size),
  );

  /// A ring when there are enough people for one, a row when there are two.
  ///
  /// This is the one game here with no geometry at all: nothing crosses from
  /// one screen to the next, so the arrangement is chosen for the people rather
  /// than for the board. A circle puts everyone facing in, every screen visible
  /// to everybody — half the fun is watching somebody else fumble their turn —
  /// and leaves each phone in front of its own player rather than in a line
  /// where the far end is somebody else's reach.
  ///
  /// Two phones cannot make a ring, and [Layouts.circle] says so by refusing
  /// rather than by drawing a very short one. Two people sit across from each
  /// other instead, which is what a row of two already is.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => lobby.phoneCount >= 3
      ? Layouts.circle(
          lobby.phones,
          instruction: 'In a circle, each phone in front of its owner.',
        )
      : Layouts.row(
          lobby.phones,
          instruction: 'Facing each other, one phone each.',
        );

  @override
  GameSim createSim(BoardContext context) => ReactionSim(context);

  @override
  GameView createView(ViewContext context) => ReactionView(context);
}
