import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'driftwood_sim.dart';
import 'driftwood_view.dart';

/// A log rides a current down one long lane spanning every phone on the table.
/// Tap near it to steer it around rocks fixed along the way; run it aground and
/// the round is lost, ride it out the far end and the table wins together.
///
/// Built on [Layouts.row] because the whole game *is* the seam: the log is in
/// continuous motion across the entire lane for the whole round, so it has to
/// physically sweep off one phone's screen and onto the next's for anyone past
/// the first one to ever get a chance to steer it.
class DriftwoodGame implements MultiscreenGame {
  const DriftwoodGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'driftwood',
    title: 'Driftwood',
    tagline: 'A log rides the current. Tap near it to steer it past the rocks.',
    goal: 'Ride it to the far bank without running aground.',
    players: PlayerCount.range(min: 2, max: 8),
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(
    lobby.phones,
    instruction:
        'Lay the phones on their sides in a row, short edges touching. The '
        'log drifts from the left end to the right — tap near it on whichever '
        'phone it is passing to nudge it up or down, away from the rocks.',
  );

  @override
  GameSim createSim(BoardContext context) => DriftwoodSim(context);

  @override
  GameView createView(ViewContext context) => DriftwoodView();
}
