import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'echo_sim.dart';
import 'echo_view.dart';

/// A ring of phones lights up in a fresh order every level. Watch it, then
/// tap it back in the same order — get it wrong and you're out.
///
/// Sits next to Reaction Time and Chronometer on the same ring, but asks for
/// none of what they measure: not raw speed, not a felt sense of elapsed
/// time, but whether you can hold an order in your head after it stops being
/// shown. Nothing crosses the seam and nothing is animated between screens —
/// like its ring-mates, what the platform buys this game is the one clock and
/// the one board every phone agrees on, so a level lights up identically
/// everywhere at once.
class EchoGame implements MultiscreenGame {
  const EchoGame();

  @override
  GameManifest get manifest => const GameManifest(
        id: 'echo',
        title: 'Echo',
        tagline: 'The ring lights up in order. Tap it back the same way.',
        goal: 'Get the order wrong and you\'re out — last one in wins.',
        // A ring needs three; below that there is no order to remember.
        players: PlayerCount.range(min: 3, max: 8),
      );

  /// A ring, each phone turned to face the player sitting behind it — the
  /// same arrangement Hot Potato uses, for the same reason: nothing here
  /// crosses to a neighbour, but everybody needs to see everybody else's
  /// seat light up.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.circle(
        lobby.phones,
        sort: PhoneSort.joinOrder,
        instruction: 'Sit in a circle with your phone flat in front of you, '
            'screen facing you. Watch the seats light up, then tap yours '
            'when it comes up again, in the same order.',
      );

  @override
  GameSim createSim(BoardContext context) => EchoSim(context);

  @override
  GameView createView(ViewContext context) => EchoView();
}
