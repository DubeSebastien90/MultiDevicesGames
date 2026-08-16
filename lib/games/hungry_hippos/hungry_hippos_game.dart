import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'hungry_hippos_sim.dart';
import 'hungry_hippos_view.dart';

/// Marbles in a shallow dish, and four hippos with no manners.
///
/// The board has to be roughly as wide as it is tall — a dish on a runway is
/// not a dish — which is why this is the one game here with a *different*
/// arrangement for every table size it accepts, and why it accepts only three.
class HungryHipposGame implements MultiscreenGame {
  const HungryHipposGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'hungryhippos',
    title: 'Hungry Hippos',
    tagline: 'Marbles in the middle. Tap to lunge. No manners required.',
    goal: 'Swallow more marbles than you have any right to.',
    // Two, four or six, and nothing between: each is a different arrangement
    // that keeps the board square enough for a dish, and there is no sensible
    // block of three or five. Said as a list because that is the truth — a
    // range with an even parity would also allow eight, which would put the
    // far phones out of anyone's reach.
    players: PlayerCount.anyOf([2, 4, 6]),
    tier: GameTier.premium,
  );

  /// One rule per table size, because a dish needs a squarish board.
  ///
  /// - **Two**: side by side, long edges touching. Two players facing each
  ///   other across the short board, which is how two people play the real toy.
  /// - **Four**: the Flood block — two rows of two. Every phone contributes an
  ///   inner corner, and the four corners meeting in the middle *are* the four
  ///   hippo positions in the original.
  /// - **Six**: the same block with a third column, which lengthens the short
  ///   side rather than making an already-tall board taller.
  ///
  /// Upright throughout: portrait phones tile into a squarer block than
  /// sideways ones, and the dish wants a square.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => lobby.phoneCount == 2
      ? Layouts.row(
          lobby.phones,
          orientation: PhoneOrientation.upright,
          instruction: 'Side by side, long edges touching.',
        )
      : Layouts.grid(
          lobby.phones,
          rows: 2,
          orientation: PhoneOrientation.upright,
          instruction: 'In a block, two rows, screens touching.',
        );

  @override
  GameSim createSim(BoardContext context) => HungryHipposSim(context);

  @override
  GameView createView(ViewContext context) => HungryHipposView(context);
}
