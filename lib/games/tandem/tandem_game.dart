import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'tandem_sim.dart';
import 'tandem_view.dart';

/// Stand in a line. When two neighbours light up, both of you tap — together.
///
/// The first game on [Layouts.column]: a straight line of phones, stacked
/// rather than side by side, with nothing physical to catch or push between
/// them. What crosses the gap here is timing, not an object — the platform's
/// single shared clock is what lets two separate screens agree a tap landed
/// inside the same shrinking window.
class TandemGame implements MultiscreenGame {
  const TandemGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'tandem',
    title: 'Tandem',
    tagline: 'Two neighbours light up together. Both tap, or it doesn\'t '
        'count.',
    goal: 'Land 8 synced taps as a table before the minute is up.',
    players: PlayerCount.range(min: 2, max: 8),
  );

  /// A single line, top to bottom, so every phone but the two ends has
  /// exactly two neighbours — and the board's own reading order already puts
  /// them next to each other in [BoardContext.slices].
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.column(
    lobby.phones,
    instruction: 'Stack the phones in a line, top to bottom. When two '
        'neighbours light up, both of you tap at once.',
  );

  @override
  GameSim createSim(BoardContext context) => TandemSim(context);

  @override
  GameView createView(ViewContext context) => TandemView(context);
}
