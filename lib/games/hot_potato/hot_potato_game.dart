import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'hot_potato_sim.dart';
import 'hot_potato_view.dart';

/// Sit in a circle and get rid of it before the fuse runs out.
///
/// The game that proves two halves of the contract at once: physics is optional
/// (its sim extends [GameSim] directly and links no engine), and a board need
/// not be a row or a column — this one is a ring of phones each turned to face
/// its own player.
class HotPotatoGame implements MultiscreenGame {
  const HotPotatoGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'hotpotato',
    title: 'Hot Potato',
    tagline: 'Swipe it to a neighbour before the fuse runs out.',
    goal: 'Holding it when it goes off costs you 10 points.',
    // Two phones would just be passing it back and forth across a table.
    players: PlayerCount.range(min: 3, max: 8),
    tier: GameTier.premium,
  );

  /// A ring. Every phone turned outward to face the person it belongs to, and
  /// deliberate space between them — the potato crossing that space is the game
  /// working, not a gap in the board.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.circle(
    lobby.phones,
    sort: PhoneSort.joinOrder,
    instruction:
        'Sit in a circle with your phone flat in front of you, screen facing '
        'you. Swipe left or right to shove the potato at a neighbour.',
  );

  @override
  GameSim createSim(BoardContext context) => HotPotatoSim(context);

  @override
  GameView createView(ViewContext context) =>
      HotPotatoView(phoneId: context.phoneId);
}
