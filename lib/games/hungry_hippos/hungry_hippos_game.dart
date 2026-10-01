import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'hungry_hippos_sim.dart';
import 'hungry_hippos_view.dart';

class HungryHipposGame implements MultiscreenGame {
  const HungryHipposGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'hungryhippos',
    title: 'Marbles Madness',
    tagline: 'Marbles in the middle. Tap to lunge. No manners required.',
    goal: 'Swallow more marbles than you have any right to.',
    icon: 'assets/icons/icones_minijeux/hungryhippos.svg',
    players: PlayerCount.anyOf([2, 4, 6]),
    tier: GameTier.premium,
  );

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
