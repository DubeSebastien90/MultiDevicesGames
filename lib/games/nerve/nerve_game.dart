import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import '../../sdk/model/player_color.dart';
import 'nerve_sim.dart';
import 'nerve_view.dart';

/// Press and hold as long as you dare — let go before the hidden threshold
/// and you bank it, hold past it and the turn is worth nothing.
///
/// No physics and no entities, the same shape as Reaction Time and
/// Chronometer: nothing crosses the seam, so the whole game lives in
/// [GameSim.sharedState]. What sets it apart from either is the decision it
/// asks for — not a reflex, not an estimate, but a fresh choice every instant
/// a finger stays down between banking what is already earned and risking it
/// for more.
class NerveGame implements MultiscreenGame {
  const NerveGame();

  @override
  GameManifest get manifest => GameManifest(
    id: 'nerve',
    title: 'Nerve',
    tagline: 'Hold your screen as long as you dare.',
    goal: 'Let go too late and the turn is worth nothing. Bank the most.',
    // Two is a straight duel of nerve; the ceiling is the palette, since
    // a turn is announced by a player's colour and two people sharing one
    // would not know whose turn — or whose glow — was whose.
    players: PlayerCount.range(min: 2, max: PlayerPalette.size),
  );

  /// A ring when there are enough people for one, a row when there are two —
  /// the same fallback Reaction Time and Chronometer use, for the same
  /// reason: nothing crosses the seam here, so the arrangement is chosen for
  /// how visible every screen is to every player, not for the board. Watching
  /// somebody else's held colour climb is half the game.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => lobby.phoneCount >= 3
      ? Layouts.circle(
          lobby.phones,
          instruction: 'In a circle, each phone in front of its owner.',
        )
      : Layouts.row(
          lobby.phones,
          instruction: 'Facing each other, one phone each.',
        );

  @override
  GameSim createSim(BoardContext context) => NerveSim(context);

  @override
  GameView createView(ViewContext context) => NerveView(context);
}
