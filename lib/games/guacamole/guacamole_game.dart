import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import '../../sdk/model/player_color.dart';
import 'guacamole_sim.dart';
import 'guacamole_view.dart';

/// Avocados pop up all over the table. Squish the ones in your colour.
///
/// The first game here that is properly competitive, and the first that needs
/// to know *who* a player is rather than merely which screen they are holding —
/// which is why [PlayerColor] had to become part of the platform.
///
/// It is also the first that does not use the seam. Nothing crosses the gap
/// between two phones; what it borrows from the platform instead is the single
/// authoritative clock and the single spawner, so that "an equal number of
/// moles for everybody" is a promise one machine can actually keep.
class GuacamoleGame implements MultiscreenGame {
  const GuacamoleGame();

  @override
  GameManifest get manifest => GameManifest(
    id: 'guacamole',
    title: 'Guac-a-Mole',
    tagline: 'Avocados pop up everywhere. Squish the ones wearing your colour.',
    goal: 'Most points when the minute is up.',
    // Below four the reaching-across-the-table game does not happen, and the
    // colours stop being the point. The ceiling is the palette.
    //
    // Even, because the board is two rows and [Layouts.grid] will not split an
    // odd table between them. Five people wanting to play is a real situation,
    // but a 3-and-2 block puts somebody at a corner nobody else can reach, and
    // refusing is more honest than pretending that is the same game.
    players: PlayerCount.range(
      min: 4,
      max: PlayerPalette.size,
      parity: CountParity.even,
    ),
    tier: GameTier.premium,
  );

  /// A block, not a strip.
  ///
  /// Every other game here wants a line, because something is travelling along
  /// it. This one wants everybody within arm's reach of everybody else's
  /// screen: your moles are mostly on other people's phones, and a two-metre
  /// row would make half of them unreachable.
  ///
  /// Upright, because a phone lying the way you would normally hold it splits
  /// into four honest quarters; on its side the quarters are wide letterboxes.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.grid(
    lobby.phones,
    // Two rows facing each other across the table, however many are playing.
    // Four phones make a 2x2; eight make a 4x2 that is still one lunge deep.
    // A third row would put the middle of the board out of everyone's reach.
    rows: 2,
    sort: PhoneSort.joinOrder,
    orientation: PhoneOrientation.upright,
    gap: Gaps.casingsTouching,
  );

  @override
  GameSim createSim(BoardContext context) => GuacamoleSim(context);

  @override
  GameView createView(ViewContext context) => GuacamoleView(context);
}
