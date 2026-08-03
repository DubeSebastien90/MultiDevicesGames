import '../../sdk/contract/game.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'slingshot_sim.dart';
import 'slingshot_view.dart';

/// Angry-Birds-in-miniature, and the game the seam was originally proved with.
class SlingshotGame implements MultiscreenGame {
  const SlingshotGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'slingshot',
    title: 'Slingshot',
    tagline: 'Pull the bird back and knock the tower down.',
    goal: 'Hit the tower to win.',
    minPhones: 1,
    maxPhones: 6,
  );

  /// A long runway. The flight is horizontal, so the board wants to be as wide
  /// as the table allows and no taller than it has to be.
  ///
  /// Smallest screen first: the sling sits at the left end and the tower at the
  /// right, so the big phone earns its place where the interesting collisions
  /// happen.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(
    lobby.phones,
    sort: PhoneSort.smallestFirst,
    align: CrossAlign.start,
    gap: Gaps.casingsTouching,
  );

  @override
  GameSim createSim(BoardContext context) => SlingshotSim(context);

  @override
  GameView createView(ViewContext context) => SlingshotView();
}
