import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'dodgeball_sim.dart';
import 'dodgeball_view.dart';

class DodgeballGame implements MultiscreenGame {
  const DodgeballGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'dodgeball',
    title: 'Dodgeball',
    tagline: 'Dodge the bouncing balls!',
    goal: 'Be the last one standing. Drag to move, tap to dash.',
    icon: 'assets/icons/icones_minijeux/dodgeball.svg',
    players: PlayerCount.range(min: 2, max: 8),
    tier: GameTier.premium,
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
  GameSim createSim(BoardContext context) => DodgeballSim(context);

  @override
  GameView createView(ViewContext context) => DodgeballView(
    phoneId: context.phoneId,
    characters: context.characters,
    roster: context.roster,
  );
}
