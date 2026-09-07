import 'package:flutter/material.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/phone_spec.dart';

/// TEMPORARY dev tool, not a real game. Forces the two phones top to top so
/// NameDrop can actually be triggered, and skips [NameDropOptimizer] so the
/// plan is not turned safe before it reaches the table.
///
/// Delete this whole folder and its [GameCatalog] entry once NameDrop testing
/// is done.
class TestInterruptionGame implements MultiscreenGame {
  const TestInterruptionGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'test_interruption',
    title: 'Test: NameDrop',
    tagline: 'Dev tool — put the two phones top to top and wait.',
    goal: 'Confirm the platform notices the interruption.',
    players: PlayerCount.exactly(2),
    skipNameDropOptimizer: true,
  );

  @override
  BoardPlan planBoard(LobbyInfo lobby) {
    final a = lobby.phones[0];
    final b = lobby.phones[1];
    final gap = a.bezelMm + b.bezelMm;

    return BoardPlan(
      [
        // Flipped, so its top (normally pointing away, up-screen) points down
        // toward the seam instead — at the other phone's top.
        PhonePlacement(
          a.phoneId,
          xMm: 0,
          yMm: -(a.heightMm / 2 + gap / 2),
          turnDeg: 180,
          hint: 'upside down, top toward the other phone',
        ),
        // Left upright: its top already points up-screen, toward the seam.
        PhonePlacement(
          b.phoneId,
          xMm: 0,
          yMm: b.heightMm / 2 + gap / 2,
          hint: 'right side up, top toward the other phone',
        ),
      ],
      instruction: 'Put the two phones top to top, touching in the middle.',
    );
  }

  @override
  GameSim createSim(BoardContext context) => TestInterruptionSim(context);

  @override
  GameView createView(ViewContext context) => TestInterruptionView();
}

class TestInterruptionSim implements GameSim {
  TestInterruptionSim(this.context);

  final BoardContext context;
  GameOutcome? _outcome;

  @override
  void step(double dt) {}

  @override
  void onTouch(TouchEvent touch) {
    // Tap anywhere, either phone, to end the test and return to the lobby.
    if (touch.phase == TouchPhase.down) {
      _outcome ??= const GameOutcome.won(summary: 'Test ended');
    }
  }

  @override
  Iterable<Entity> get entities => const [];

  @override
  Map<String, Object?> get sharedState => const {};

  @override
  GameOutcome? get outcome => _outcome;

  @override
  void reset() => _outcome = null;

  @override
  void dispose() {}
}

class TestInterruptionView implements GameView {
  @override
  Future<void> load() async {}

  @override
  void render(Canvas canvas, Frame frame) {}

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Bring the TOPS of the two phones together, like NameDrop.\n\n'
        'Watch the debug console for [namedrop] logs.\n\n'
        'Tap anywhere to end the test.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 18, height: 1.4),
      ),
    ),
  );

  @override
  void dispose() {}
}
