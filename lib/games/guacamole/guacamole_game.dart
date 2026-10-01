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

class GuacamoleGame implements MultiscreenGame {
  const GuacamoleGame();

  @override
  GameManifest get manifest => GameManifest(
    id: 'guacamole',
    title: 'Guac-a-Mole',
    tagline: 'Avocados pop up everywhere. Squish the ones wearing your colour.',
    goal: 'Most points when the minute is up.',
    icon: 'assets/icons/icones_minijeux/guacamole.svg',
    players: PlayerCount.range(min: 3, max: PlayerPalette.size),
    tier: GameTier.premium,
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) {
    final phones = lobby.phones;
    if (phones.length.isEven) {
      return Layouts.grid(
        phones,
        rows: 2,
        sort: PhoneSort.joinOrder,
        orientation: PhoneOrientation.upright,
        gap: Gaps.casingsTouching,
      );
    }
    return Layouts.brick(
      phones.length == 3 ? Layouts.shortestLast(phones) : phones,
      sort: PhoneSort.joinOrder,
      orientation: PhoneOrientation.upright,
      gap: Gaps.casingsTouching,
    );
  }

  @override
  GameSim createSim(BoardContext context) => GuacamoleSim(context);

  @override
  GameView createView(ViewContext context) => GuacamoleView(context);
}
