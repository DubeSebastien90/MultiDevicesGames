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
    icon: 'assets/icons/icones_minijeux/pitch_cars.svg',
    players: PlayerCount.range(min: 2, max: 8),
  );

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
      PitchCarsView(roster: context.roster);
}
