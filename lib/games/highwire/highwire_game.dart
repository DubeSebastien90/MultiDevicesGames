import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'highwire_sim.dart';
import 'highwire_view.dart';

/// One walker, one wire strung the length of the table.
///
/// Whichever phone's screen the walker is crossing has to hold its own screen
/// down or the walker's balance drains and it falls. No steering, no impulses
/// — the only thing a player ever does is keep contact while it is theirs to
/// keep, which is what makes the handoff at the seam the entire game.
class HighwireGame implements MultiscreenGame {
  const HighwireGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'highwire',
    title: 'Highwire',
    tagline: 'One walker, one wire strung the length of the table.',
    goal:
        "Hold your screen while the walker is on it — let go and their "
        'balance runs out.',
    // Below two phones there is no seam for the walker to be handed across.
    players: PlayerCount.range(min: 2, max: 8),
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(
    lobby.phones,
    instruction:
        'Lay the phones on their sides in a row, short edges touching — the '
        'wire runs the whole length.',
  );

  @override
  GameSim createSim(BoardContext context) => HighwireSim(context);

  @override
  GameView createView(ViewContext context) =>
      HighwireView(phoneId: context.phoneId);
}
