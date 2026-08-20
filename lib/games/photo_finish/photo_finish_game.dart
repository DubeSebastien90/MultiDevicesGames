import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'photo_finish_sim.dart';
import 'photo_finish_view.dart';

/// Tap to sprint your own runner the length of the whole row.
class PhotoFinishGame implements MultiscreenGame {
  const PhotoFinishGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'photo_finish',
    title: 'Photo Finish',
    tagline: 'Tap to sprint your runner down the lane.',
    goal: 'First runner across the far line wins.',
    // Capped below the usual eight: every runner needs its own lane on a
    // board only one phone's short edge tall, and eight of them would leave
    // less than a runner's width each.
    players: PlayerCount.range(min: 2, max: 6),
  );

  /// The same wide, short runway Slingshot's board is — except this time
  /// every phone on it is a finish line for somebody's *own* runner, not a
  /// target for one shared shot.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(lobby.phones);

  @override
  GameSim createSim(BoardContext context) => PhotoFinishSim(context);

  @override
  GameView createView(ViewContext context) => PhotoFinishView();
}
