import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'subway_skater_sim.dart';
import 'subway_skater_view.dart';

/// A three-lane corridor running the length of the table, and a queue of people
/// dodging down it.
///
/// The line is the whole game: your place in it pays out every tick, the front
/// pays most and meets everything first, and being clipped tumbles you to the
/// back and moves everyone behind you up one. Nobody holds the front for the
/// whole round, and everybody gets a turn at running point.
class SubwaySkaterGame implements MultiscreenGame {
  const SubwaySkaterGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'subway_skater',
    title: 'Road Runner',
    tagline:
        'Swipe to dodge. The front of the line scores most and gets hit '
        'first.',
    goal: 'Spend as much of the round as far up the line as you can.',
    icon: 'assets/icons/icones_minijeux/subway_skater.svg',
    // Two is a line, barely — one hit and you have swapped ends. Beyond about
    // eight the corridor is longer than anybody can watch at once.
    players: PlayerCount.range(min: 2, max: 8),
  );

  /// One long corridor, phones on their sides, short edges touching — the same
  /// runway a launch game uses, for the same reason: the action travels the length
  /// of the table and wants every centimetre of it.
  ///
  /// Joined in the order people connected rather than by size. Every place in
  /// the line is played by everybody before the round is out, so sorting by
  /// screen would be arranging the table around a position nobody keeps.
  ///
  /// Centred across, because the three lanes are cut from the band that *every*
  /// screen can show: aligned to one edge, a shorter phone in the middle would
  /// have its outside lane running off the glass.
  @override
  BoardPlan planBoard(LobbyInfo lobby) => Layouts.row(
    lobby.phones,
    sort: PhoneSort.joinOrder,
    align: CrossAlign.center,
    gap: Gaps.casingsTouching,
    instruction:
        'Lay the phones on their sides in one long line, short edges '
        'touching and centred on each other — it is one corridor.',
  );

  @override
  GameSim createSim(BoardContext context) => SubwaySkaterSim(context);

  @override
  GameView createView(ViewContext context) => SubwaySkaterView(context);
}
