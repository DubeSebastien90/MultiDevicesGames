import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'copycat_sim.dart';
import 'copycat_view.dart';

/// Watch the tiles light up, then tap them back — together, in order.
///
/// A shared game of Simon played across the whole table: one phone lights up
/// at a time and the team repeats the sequence, which grows by one tile every
/// time they get it right. It is the first cooperative memory game here —
/// every other timed game is either a race (Pitch Cars), a reflex test
/// (Reaction Time, Chronometer) or a fight for individual points (Guac-a-Mole,
/// Hungry Hippos) — and the first game to actually lose as a team rather than
/// simply running out of time on a score attack.
class CopycatGame implements MultiscreenGame {
  const CopycatGame();

  @override
  GameManifest get manifest => const GameManifest(
        id: 'copycat',
        title: 'Copycat',
        tagline: 'Watch the tiles light up. Tap them back in order — '
            'together.',
        goal: 'Replay a pattern eight tiles long without a wrong tap.',
        players: PlayerCount.range(min: 2, max: 6),
      );

  /// A row of screens standing upright, shoulder to shoulder — a keyboard of
  /// coloured keys, one per phone.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(
        lobby.phones,
        orientation: PhoneOrientation.upright,
        align: CrossAlign.center,
        gap: Gaps.casingsTouching,
        instruction: 'Line up shoulder to shoulder, screens upright and '
            'touching — every phone is one key.',
      );

  @override
  GameSim createSim(BoardContext context) => CopycatSim(context);

  @override
  GameView createView(ViewContext context) => CopycatView();
}
