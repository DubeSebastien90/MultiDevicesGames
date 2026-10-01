import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'arena_sim.dart';
import 'arena_view.dart';

class ArenaGame implements MultiscreenGame {
  const ArenaGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'arena',
    title: 'Arena',
    tagline: 'Fight to be the last one standing.',
    goal: 'Eliminate everyone. Drag, tap, hold.',
    icon: 'assets/icons/icones_minijeux/arena.svg',
    players: PlayerCount.range(min: 2, max: 8),
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) {
    final n = lobby.phones.length;

    if (n < 2) {
      return Layouts.row(
        lobby.phones,
        sort: PhoneSort.joinOrder,
        orientation: PhoneOrientation.sideways,
        gap: Gaps.casingsTouching,
      );
    }
    if (n.isEven) {
      return Layouts.grid(
        lobby.phones,
        rows: 2,
        sort: PhoneSort.joinOrder,
        orientation: PhoneOrientation.sideways,
        gap: Gaps.casingsTouching,
        instruction: n == 2
            ? 'One phone above the other, both on their sides, long edges '
                  'touching.'
            : 'Two rows facing each other, phones on their sides, '
                  'edges touching.',
      );
    }

    return Layouts.brick(
      n == 3 ? Layouts.shortestLast(lobby.phones) : lobby.phones,
      sort: PhoneSort.joinOrder,
      orientation: PhoneOrientation.sideways,
      gap: Gaps.casingsTouching,
      instruction: n == 3
          ? 'Two phones on their sides, short edges touching; '
                'the third below them, across the join.'
          : null,
    );
  }

  @override
  GameSim createSim(BoardContext context) => ArenaSim(context);

  @override
  GameView createView(ViewContext context) => ArenaView(
    phoneId: context.phoneId,
    characters: context.characters,
    roster: context.roster,
  );
}
