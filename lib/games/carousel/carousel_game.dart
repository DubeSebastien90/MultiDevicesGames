import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'carousel_sim.dart';
import 'carousel_view.dart';

/// A marker spins round the ring. Land it in your own zone to score.
///
/// The ring paired with a body that actually travels round it rather than
/// hopping seat to seat (Hot Potato) or lighting one seat at a time (Reaction,
/// Chronometer, Echo, Nerve) — Carousel is the one game here where something
/// moves continuously along the circle itself.
class CarouselGame implements MultiscreenGame {
  const CarouselGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'carousel',
    title: 'Carousel',
    tagline: 'A marker spins round the ring. Tap to push it — or let it die '
        'in your zone.',
    goal: 'First to 5 landings wins the round.',
    // Two phones would just be a marker bouncing between them; the whole
    // point is a ring of distinct zones to strand it in.
    players: PlayerCount.range(min: 3, max: 8),
  );

  /// A ring, exactly like Hot Potato's — each phone turned to face its own
  /// player, with real space between screens for the marker to sweep through.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.circle(
    lobby.phones,
    sort: PhoneSort.joinOrder,
    instruction:
        'Sit in a circle with your phone flat in front of you, screen facing '
        'you. Tap your screen to spin the marker on — it slows down on its '
        'own and lands wherever it runs out of steam.',
  );

  @override
  GameSim createSim(BoardContext context) => CarouselSim(context);

  @override
  GameView createView(ViewContext context) => CarouselView();
}
