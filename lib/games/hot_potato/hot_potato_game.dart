import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'hot_potato_sim.dart';
import 'hot_potato_view.dart';

class HotPotatoGame implements MultiscreenGame {
  const HotPotatoGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'hotpotato',
    title: 'Hot Potato',
    tagline: 'Swipe it to a neighbour before the fuse runs out.',
    goal: "Don't be holding it — or next to it — when it blows.",
    icon: 'assets/icons/icones_minijeux/hotpotato.svg',
    players: PlayerCount.range(min: 3, max: 8),
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.circle(
    lobby.phones,
    sort: PhoneSort.joinOrder,
    instruction:
        'Sit in a circle with your phone flat in front of you, screen facing '
        'you. Swipe up or down to throw the potato to a neighbour.',
  );

  @override
  GameSim createSim(BoardContext context) => HotPotatoSim(context);

  @override
  GameView createView(ViewContext context) =>
      HotPotatoView(phoneId: context.phoneId, roster: context.roster);
}
