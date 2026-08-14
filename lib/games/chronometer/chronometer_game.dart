import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import '../../sdk/model/player_color.dart';
import 'chronometer_sim.dart';
import 'chronometer_view.dart';

/// A number, then a blank screen. Press when you think it has elapsed.
///
/// The sibling of Reaction Time and its exact inverse: that one measures how
/// fast you notice something, this one measures how well you keep time with
/// nothing to look at. It leans on the platform for the same single hard part —
/// one clock, one starting instant — so that two people pressing at the same
/// real moment get the same number.
class ChronometerGame implements MultiscreenGame {
  const ChronometerGame();

  @override
  GameManifest get manifest => GameManifest(
        id: 'chronometer',
        title: 'Chronometer',
        tagline: 'A number, then a blank screen. Press when it has elapsed.',
        goal: 'The closest guess when everybody has pressed.',
        // Two is a contest; alone there is nobody to be closer than. The
        // ceiling is the palette, because a guess is announced by its owner's
        // colour and two people sharing one could not tell their pips apart.
        players: PlayerCount.range(min: 2, max: PlayerPalette.size),
      );

  /// A star: every phone upright in its own hand, pointing at the middle.
  ///
  /// [RingFacing.radial] rather than the default tangential, so each phone's
  /// long axis runs along its own radius — three players make a three-armed
  /// star, five make a five-armed one. That is the arrangement people actually
  /// adopt when they put a phone down in front of themselves at a round table,
  /// and it leaves each screen the right way round for its owner rather than
  /// lying on its side like a tile in a wheel.
  ///
  /// The turns this hands out are real and deliberate: the placement screen
  /// draws them, and they are how a player knows which way to lay their phone
  /// down. **The view is what makes the picture read upright** — it counters
  /// the camera's rotation when it draws, which is the right place for the fix
  /// because it is a fact about this game's pixels and not about where the
  /// phones go. See [ChronometerView].
  ///
  /// Two phones cannot make a ring, and [Layouts.circle] says so by refusing
  /// rather than by drawing a very short one. Two people sit across from each
  /// other instead, which is what a row of two already is.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => lobby.phoneCount >= 3
      ? Layouts.circle(
          lobby.phones,
          facing: RingFacing.radial,
          instruction: 'In a circle, each phone upright in front of its owner, '
              'pointing at the middle.',
        )
      : Layouts.row(
          lobby.phones,
          orientation: PhoneOrientation.upright,
          instruction: 'Facing each other, one phone each.',
        );

  @override
  GameSim createSim(BoardContext context) => ChronometerSim(context);

  @override
  GameView createView(ViewContext context) => ChronometerView(context);
}
