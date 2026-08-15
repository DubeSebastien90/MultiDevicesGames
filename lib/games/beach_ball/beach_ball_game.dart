import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'beach_ball_sim.dart';
import 'beach_ball_view.dart';

/// A ball falls under gravity across a row of phones. Tap under it while it
/// is falling to bump it back up — miss, and it hits the ground.
class BeachBallGame implements MultiscreenGame {
  const BeachBallGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'beachball',
    title: 'Beach Ball',
    tagline: 'A ball wants to hit the ground. Tap under it to keep it up.',
    goal: 'Keep it airborne for 25 seconds — together.',
    players: PlayerCount.range(min: 2, max: 6),
  );

  /// Phones standing upright in a row, side by side — a court read from the
  /// side, tall enough that the ball spends real time in the air between
  /// bumps rather than skimming past.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(
    lobby.phones,
    sort: PhoneSort.joinOrder,
    orientation: PhoneOrientation.upright,
    gap: Gaps.casingsTouching,
    instruction: 'Stand the phones up in a row, side by side, long edges '
        'touching.',
  );

  @override
  GameSim createSim(BoardContext context) => BeachBallSim(context);

  @override
  GameView createView(ViewContext context) => BeachBallView();
}
