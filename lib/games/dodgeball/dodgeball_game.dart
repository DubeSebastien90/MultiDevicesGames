import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'dodgeball_sim.dart';
import 'dodgeball_view.dart';

/// Dodge bouncing balls — last one standing wins.
///
/// Players control a character via drag-to-move. Balls spawn from walls and
/// bounce diagonally, getting faster over time. Tap to dash with a cooldown.
class DodgeballGame implements MultiscreenGame {
  const DodgeballGame();

  @override
  GameManifest get manifest => const GameManifest(
        id: 'dodgeball',
        title: 'Dodgeball',
        tagline: 'Dodge the bouncing balls!',
        goal: 'Be the last one standing. Drag to move, tap to dash.',
        players: PlayerCount.range(min: 2, max: 8),
      );

  @override
  BoardPlan planBoard(LobbyInfo lobby) {
    final n = lobby.phones.length;
    if (n <= 3) {
      return Layouts.row(
        lobby.phones,
        sort: PhoneSort.joinOrder,
        orientation: PhoneOrientation.sideways,
        gap: Gaps.casingsTouching,
        instruction: 'Lay your phones side by side on their sides, '
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
        instruction: 'Two rows facing each other, phones on their sides, '
            'edges touching.',
      );
    }
    return Layouts.row(
      lobby.phones,
      sort: PhoneSort.joinOrder,
      orientation: PhoneOrientation.sideways,
      gap: Gaps.casingsTouching,
      instruction: 'Lay your phones side by side on their sides, '
          'short edges touching.',
    );
  }

  @override
  GameSim createSim(BoardContext context) => DodgeballSim(context);

  @override
  GameView createView(ViewContext context) =>
      DodgeballView(phoneId: context.phoneId);
}
