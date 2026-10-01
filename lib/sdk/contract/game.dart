import '../layout/board_plan.dart';
import 'player_count.dart';
import '../layout/phone_spec.dart';
import 'sim.dart';
import 'view.dart';

enum GameTier { free, premium }

class GameManifest {
  const GameManifest({
    required this.id,
    required this.title,
    required this.tagline,
    required this.goal,
    this.icon,
    this.players = const PlayerCount.range(min: 1),
    this.supportsIpad = false,
    this.tier = GameTier.free,
    this.skipNameDropOptimizer = false,
  });

  final String id;

  final String title;

  final String tagline;

  final String goal;

  final String? icon;

  final PlayerCount players;

  final bool supportsIpad;

  final GameTier tier;

  bool get isPremium => tier == GameTier.premium;

  final bool skipNameDropOptimizer;

  bool fits(int phoneCount) => players.fits(phoneCount);

  String requirement() => players.describe();

  int get smallestTable => players.smallest;
}

abstract class MultiscreenGame {
  GameManifest get manifest;

  BoardPlan planBoard(LobbyInfo lobby);

  GameSim createSim(BoardContext context);

  GameView createView(ViewContext context);
}
