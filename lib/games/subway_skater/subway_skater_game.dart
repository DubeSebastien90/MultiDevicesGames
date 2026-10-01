import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'subway_skater_sim.dart';
import 'subway_skater_view.dart';

class SubwaySkaterGame implements MultiscreenGame {
  const SubwaySkaterGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'subway_skater',
    title: 'Road Runner',
    tagline:
        'Swipe to dodge. The front of the line scores most and gets hit '
        'first.',
    goal: 'Spend as much of the round as far up the line as you can.',
    icon: 'assets/icons/icones_minijeux/subway_skater.svg',
    players: PlayerCount.range(min: 2, max: 8),
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(
    lobby.phones,
    sort: PhoneSort.joinOrder,
    align: CrossAlign.center,
    gap: Gaps.casingsTouching,
    instruction:
        'Lay the phones on their sides in one long line, short edges '
        'touching and centred on each other — it is one corridor.',
  );

  @override
  GameSim createSim(BoardContext context) => SubwaySkaterSim(context);

  @override
  GameView createView(ViewContext context) => SubwaySkaterView(context);
}
