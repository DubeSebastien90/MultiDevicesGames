import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'push_of_war_sim.dart';
import 'push_of_war_view.dart';

/// A ball at the middle of a long lane. Tap your side to shove it toward the
/// other team; push it past their line to win.
class PushOfWarGame implements MultiscreenGame {
  const PushOfWarGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'pushofwar',
    title: 'Push of War',
    tagline:
        'Tap your side of the table to shove the ball toward the other team.',
    goal: 'Push the ball past the far line to win.',
    // Two equal teams, one on each end of the lane.
    players: PlayerCount.range(min: 2, max: 8, parity: CountParity.even),
  );

  /// A wide, short lane — the runway a ball rolls down, with a team camped
  /// at either end.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(lobby.phones);

  @override
  GameSim createSim(BoardContext context) => PushOfWarSim(context);

  @override
  GameView createView(ViewContext context) => PushOfWarView();
}
