import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import '../../sdk/model/player_color.dart';
import 'fusebox_sim.dart';
import 'fusebox_view.dart';

/// A shared game of Lights Out. Every screen is one light; a tap trips it and
/// its neighbours. Go dark together before the breaker trips.
///
/// The first puzzle on the platform rather than a reflex test, a memory test,
/// a race or a tug-of-war: the challenge is entirely in reasoning about a
/// deterministic board, and the table either works it out together or it
/// does not. It borrows Guac-a-Mole's block layout for the same reason
/// Guac-a-Mole picked it — everybody needs to see and reach every light — but
/// nothing else about the two games is alike: nothing spawns, nothing is
/// timed per-object, and no colour scores anybody.
class FuseBoxGame implements MultiscreenGame {
  const FuseBoxGame();

  @override
  GameManifest get manifest => GameManifest(
    id: 'fusebox',
    title: 'Fuse Box',
    tagline: 'Every tap trips your light and its neighbours.',
    goal: 'Turn every light off together before the breaker trips.',
    // Even, because the board is two rows and Layouts.grid will not split an
    // odd table between them. Four is where a 2x2 puzzle first has more than
    // one light to reason about; the ceiling is the palette-sized block
    // Guac-a-Mole already settled on for the same shape of table.
    players: PlayerCount.range(
      min: 4,
      max: PlayerPalette.size,
      parity: CountParity.even,
    ),
  );

  /// A block, not a strip — the same two rows facing each other that
  /// Guac-a-Mole uses, so every light is within arm's reach of everybody.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.grid(
    lobby.phones,
    rows: 2,
    sort: PhoneSort.joinOrder,
    orientation: PhoneOrientation.upright,
    gap: Gaps.casingsTouching,
  );

  @override
  GameSim createSim(BoardContext context) => FuseBoxSim(context);

  @override
  GameView createView(ViewContext context) => FuseBoxView(context);
}
