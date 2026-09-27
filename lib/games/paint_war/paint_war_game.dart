import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'paint_war_sim.dart';
import 'paint_war_view.dart';

/// Paint the table: walk out of your colour, loop back, and everything the loop
/// closed off is yours. Touch somebody's wet trail and they are wiped off.
class PaintWarGame implements MultiscreenGame {
  const PaintWarGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'paintwar',
    title: 'Paint War',
    tagline: 'Loop out of your colour to claim the table. Cut the others.',
    goal: 'The biggest territory when the minute is up.',
    players: PlayerCount.range(min: 2, max: 8),
  );

  /// The same table as Arena and Dodgeball: phones on their sides, in a row
  /// for two, two rows facing each other for an even table, and bricks for an
  /// odd one — one more on top, rows centred.
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
  GameSim createSim(BoardContext context) => PaintWarSim(context);

  @override
  GameView createView(ViewContext context) => PaintWarView(
    phoneId: context.phoneId,
    characters: context.characters,
    roster: context.roster,
  );
}
