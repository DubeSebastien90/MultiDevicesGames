import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'cops_robbers_sim.dart';
import 'cops_robbers_view.dart';

class CopsRobbersGame implements MultiscreenGame {
  const CopsRobbersGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'copsrobbers',
    title: 'Cops & Robbers',
    tagline: 'Grab the cash, or catch the robbers. Then swap.',
    goal: 'Your team grabs more cash in its turn than theirs.',
    icon: 'assets/icons/icones_minijeux/copsrobbers.svg',
    players: PlayerCount.range(min: 2, max: 8, parity: CountParity.even),
    tier: GameTier.premium,
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.grid(
    lobby.phones,
    rows: 2,
    sort: PhoneSort.joinOrder,
    orientation: PhoneOrientation.sideways,
    gap: Gaps.casingsTouching,
    instruction: lobby.phones.length == 2
        ? 'One phone above the other, both on their sides, long edges '
              'touching. Each phone is a team.'
        : 'Two rows facing each other, phones on their sides, '
              'edges touching. Each row is a team.',
  );

  @override
  GameSim createSim(BoardContext context) => CopsRobbersSim(context);

  @override
  GameView createView(ViewContext context) => CopsRobbersView(
    phoneId: context.phoneId,
    characters: context.characters,
    roster: context.roster,
  );
}
