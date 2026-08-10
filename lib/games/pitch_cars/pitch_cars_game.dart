import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'pitch_cars_sim.dart';
import 'pitch_cars_view.dart';

class PitchCarsGame implements MultiscreenGame {
  const PitchCarsGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'pitch_cars',
    title: 'Pitch Cars',
    tagline: 'Flick your car around a randomized track.',
    goal: 'First past the finish line.',
    players: PlayerCount.range(min: 2, max: 8),
  );

  /// A winding path, different every round.
  ///
  /// The platform's own helper rather than a generator of this game's: the
  /// track is built from the compiled board — it recovers the chain and reads
  /// the seams off the connectors — so what it needs is a chain of phones each
  /// meeting only the one before it, which is exactly what [Layouts.path]
  /// promises. Two things this game used to keep for itself are now the
  /// helper's, and every game gets them.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.path(
    lobby.phones,
    instruction:
        'Lay the phones out to match the coloured edges — the track '
        'winds along it, start to finish.',
  );

  @override
  GameSim createSim(BoardContext context) => PitchCarsSim(context);

  @override
  GameView createView(ViewContext context) =>
      PitchCarsView(phoneId: context.phoneId);
}
