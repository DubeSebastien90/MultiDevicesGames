import '../../sdk/contract/game.dart';
import '../../sdk/contract/player_count.dart';
import '../../sdk/contract/sim.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/layout/board_plan.dart';
import '../../sdk/layout/layouts.dart';
import '../../sdk/layout/phone_spec.dart';
import 'chomp_chase_sim.dart';
import 'chomp_chase_view.dart';

/// Two teams in one maze: half chomp the dots while the other half hunt them
/// as ghosts, then they swap. Most dots eaten wins.
class ChompChaseGame implements MultiscreenGame {
  const ChompChaseGame();

  @override
  GameManifest get manifest => const GameManifest(
    id: 'chompchase',
    title: 'Chomp Chase',
    tagline: 'Chomp the dots, or hunt the chompers. Then swap.',
    goal: 'Your team eats more dots in its turn than theirs.',
    // Two equal teams, so an even table: one against one up to four a side.
    players: PlayerCount.range(min: 2, max: 8, parity: CountParity.even),
  );

  /// The same table as Arena and Dodgeball, phones on their sides: a row for
  /// two, two rows facing each other beyond that. Each side of the table is a
  /// team. The maze is the rectangle every screen can show — the layouts hand
  /// back exactly that as the board — and a bigger phone's spare glass is
  /// painted as wall.
  @override
  BoardPlan planBoard(LobbyInfo lobby) {
    if (lobby.phones.length <= 2) {
      return Layouts.row(
        lobby.phones,
        sort: PhoneSort.joinOrder,
        orientation: PhoneOrientation.sideways,
        gap: Gaps.casingsTouching,
        instruction:
            'Lay your phones side by side on their sides, '
            'short edges touching.',
      );
    }
    return Layouts.grid(
      lobby.phones,
      rows: 2,
      sort: PhoneSort.joinOrder,
      orientation: PhoneOrientation.sideways,
      gap: Gaps.casingsTouching,
      instruction:
          'Two rows facing each other, phones on their sides, '
          'edges touching. Each row is a team.',
    );
  }

  @override
  GameSim createSim(BoardContext context) => ChompChaseSim(context);

  @override
  GameView createView(ViewContext context) =>
      ChompChaseView(phoneId: context.phoneId, roster: context.roster);
}
