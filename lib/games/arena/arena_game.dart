import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'arena_sim.dart';
import 'arena_view.dart';

/// Last-fighter-standing arena brawler.
///
/// Players control a character on their phone via touch gestures: drag to move,
/// tap to attack in a cone, hold to block. Last one alive wins.
class ArenaGame implements MultiscreenGame {
  const ArenaGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'arena',
    title: 'Arena',
    tagline: 'Fight to be the last one standing.',
    goal: 'Eliminate everyone. Drag, tap, hold.',
    players: PlayerCount.range(min: 2, max: 8),
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) {
    final n = lobby.phones.length;
    if (n <= 2) {
      return Layouts.row(
        lobby.phones,
        sort: PhoneSort.joinOrder,
        orientation: PhoneOrientation.sideways,
        gap: Gaps.casingsTouching,
        instruction:
            'Lay your phones side by side on their sides, '
            'short edges touching.',
      );
    }
    if (n.isEven) {
      return Layouts.grid(
        lobby.phones,
        rows: 2,
        sort: PhoneSort.joinOrder,
        orientation: PhoneOrientation.sideways,
        gap: Gaps.casingsTouching,
        instruction:
            'Two rows facing each other, phones on their sides, '
            'edges touching.',
      );
    }
    // Odd: a grid with one more phone on top, the rows centred like bricks.
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
