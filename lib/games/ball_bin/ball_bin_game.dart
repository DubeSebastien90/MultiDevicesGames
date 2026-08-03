import '../../sdk/contract/game.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'ball_bin_sim.dart';
import 'ball_bin_view.dart';

/// Catch falling balls in a sliding bin.
class BallBinGame implements MultiscreenGame {
  const BallBinGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'ballbin',
    title: 'Ball Bin',
    tagline: 'Balls fall down the screens. Slide the bin and catch them.',
    goal: 'Catch 10 balls to win.',
    // One phone makes for a very short drop, and the game is about the fall.
    minPhones: 2,
    maxPhones: 5,
  );

  /// A tall well. Balls need somewhere to fall *from*, so the phones stack.
  ///
  /// Largest last puts the biggest screen at the bottom, where the bin lives
  /// and where all the aiming happens — and it gives the widest possible
  /// catching lane, since the board is only as wide as its narrowest phone.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.column(
    lobby.phones,
    sort: PhoneSort.largestLast,
    align: CrossAlign.center,
    gap: Gaps.casingsTouching,
  );

  @override
  GameSim createSim(BoardContext context) => BallBinSim(context);

  /// No custom art yet: the default renderer draws the shapes, and the view
  /// only adds the catch counter on top.
  @override
  GameView createView(ViewContext context) => BallBinView();
}
