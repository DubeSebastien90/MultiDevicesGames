import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'random_path_sim.dart';
import 'random_path_view.dart';

/// A board that is never the same twice, and no game on top of it.
///
/// Every other game here asks for an arrangement it can rely on: a runway, a
/// well, a ring. This one asks for a *path* — each phone against an edge of the
/// last, turning wherever it likes — and is otherwise empty, so what is being
/// tried out is the arrangement itself and the stripes that explain it.
class RandomPathGame implements MultiscreenGame {
  const RandomPathGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'randompath',
    title: 'Random Path',
    tagline: 'A different shape every round. Follow the coloured edges.',
    goal: 'Lay the path out. Five seconds later everybody has won.',
    // Two phones already make a path with a turn in it; below that there is no
    // arrangement to speak of.
    players: PlayerCount.range(min: 2),
  );

  /// **Different every round**, which no other layout here is.
  ///
  /// `planBoard` runs once, on the host, when the round starts — so the shape is
  /// settled before anybody is told anything, and holds for that whole round.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.path(lobby.phones);

  @override
  GameSim createSim(BoardContext context) => RandomPathSim(context);

  @override
  GameView createView(ViewContext context) => RandomPathView(context);
}
