import 'dart:math' as math;

import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'pitch_cars_sim.dart';

class PitchCarsGame implements MultiscreenGame {
  const PitchCarsGame();

  @override
  GameManifest get manifest => const GameManifest(
        id: 'pitch_cars',
        title: 'Pitch Cars',
        tagline: 'Flick your car around a randomized track.',
        goal: 'First past the finish line.',
        players: PlayerCount.range(min: 2, max: 4),
      );

  @override
  BoardPlan planBoard(LobbyInfo lobby) {
    final loopEligible = lobby.phoneCount == 4;
    final wantsLoop = loopEligible && math.Random().nextBool();
    if (wantsLoop) {
      return Layouts.circle(
        lobby.phones,
        sort: PhoneSort.joinOrder,
        instruction: 'Arrange your phones in a ring with a gap in the '
            'middle — the track runs around the outside. One lap wins.',
      );
    }
    return Layouts.row(
      lobby.phones,
      sort: PhoneSort.joinOrder,
      align: CrossAlign.start,
      gap: Gaps.casingsTouching,
      instruction: 'Lay the phones in a row — the track winds across them '
          'from left to right. First to the finish wins.',
    );
  }

  @override
  GameSim createSim(BoardContext context) => PitchCarsSim(context);

  @override
  GameView createView(ViewContext context) => throw UnimplementedError(
      'PitchCarsView is wired up in Task 5/6 of the implementation plan');
}
