import 'package:flutter/material.dart';

import '../model/player_color.dart';
import '../render/player_art.dart';
import '../score/scoreboard.dart';
import 'lobby_flow_style.dart';
import 'results_view.dart' show VerdictMark;

/// The end of the run: who won the whole evening.
///
/// The results screen after each round answers "what just happened". This one
/// answers the only question left once the playlist is spent — and it is a
/// different question, so it gets its own screen rather than a bigger card at
/// the bottom of the last round's.
///
/// Every phone shows it at once, because the standings belong to the table
/// rather than to the device running the session. Only the host is given a way
/// off it: the way out is the same as everywhere else, one person deciding for
/// the room.
class ScoreboardView extends StatelessWidget {
  const ScoreboardView({
    super.key,
    required this.scores,
    required this.meId,
    this.colors = const {},
    this.offline = const <String>{},
    this.onBackToLobby,
  });

  final ScoreView scores;
  final String? meId;

  /// Each phone's character, so a row is recognisable to somebody who has spent
  /// the evening being the frog. Missing entries simply get no portrait.
  final Map<String, PlayerColor?> colors;

  /// Phones the session remembers that are not here any more. They keep their
  /// place — they played for it — and the row says where they went.
  final Set<String> offline;

  /// Wind the session back to the lobby, or null on a phone that cannot.
  final VoidCallback? onBackToLobby;

  @override
  Widget build(BuildContext context) {
    final ranked = scores.ranked;

    // Ties share a place, so two people level on 40 are both second rather than
    // one of them being told they came third by the order of a list.
    final places = _places(ranked);

    // Whether this phone is the one being congratulated. The mark is the same
    // one the results screen uses, and it should not be celebrating at somebody
    // who came fourth.
    final won = scores.isUsed && scores.leader?.phoneId == meId;

    return Scaffold(
      backgroundColor: LobbyFlowColors.paper,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: VerdictMark(won: won)),
                  const SizedBox(height: 16),
                  LobbyTitle(_headline(scores, meId), fontSize: 30),
                  const SizedBox(height: 6),
                  Text(
                    'Final standings',
                    style: LobbyText.body.copyWith(letterSpacing: 2),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Deliberately not a [StandingsCard]: that one draws nothing
                  // at all until somebody scores, which is right where it sits —
                  // beside other things — and wrong here, where it is the whole
                  // screen. A co-operative run that ended level still has to
                  // show the table its own names.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 14,
                    ),
                    decoration: BoxDecoration(
                      color: LobbyFlowColors.field,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Column(
                      children: [
                        for (final (i, entry) in ranked.indexed)
                          _Row(
                            place: places[i],
                            entry: entry,
                            me: entry.phoneId == meId,
                            away: offline.contains(entry.phoneId),
                            color: colors[entry.phoneId],
                            // Medals mean nothing on a board nobody scored on.
                            medals: scores.isUsed,
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 26),
                  if (onBackToLobby != null)
                    LobbyPillButton(
                      onPressed: onBackToLobby,
                      icon: Icons.meeting_room_outlined,
                      label: 'Back to lobby',
                      background: LobbyFlowColors.green,
                      foreground: LobbyFlowColors.ink,
                      fontSize: 18,
                      iconSize: 22,
                      radius: LobbyMetrics.bigRadius,
                      padding: const EdgeInsets.symmetric(
                        vertical: 18,
                        horizontal: 20,
                      ),
                    )
                  else
                    // Something to look at, so a phone with no button does not
                    // read as a phone that has frozen.
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: LobbyFlowColors.muted,
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('Waiting for the host…', style: LobbyText.body),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The one line worth reading from across the table.
  static String _headline(ScoreView scores, String? meId) {
    if (!scores.isUsed) return 'That is the lot';

    final winner = scores.leader;
    // Null means the top two are level. Naming one of them would be a lie, and
    // naming neither is the actual result.
    if (winner == null) return 'It is a tie!';
    return winner.phoneId == meId ? 'You win!' : '${winner.label} wins!';
  }

  /// Standard competition ranking: 1, 2, 2, 4.
  static List<int> _places(List<ScoreEntry> ranked) {
    final places = <int>[];
    for (var i = 0; i < ranked.length; i++) {
      if (i > 0 && ranked[i].total == ranked[i - 1].total) {
        places.add(places[i - 1]);
      } else {
        places.add(i + 1);
      }
    }
    return places;
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.place,
    required this.entry,
    required this.me,
    required this.away,
    required this.color,
    required this.medals,
  });

  final int place;
  final ScoreEntry entry;
  final bool me;
  final bool away;
  final PlayerColor? color;
  final bool medals;

  /// The character, where a ten-pixel dot of their colour used to be.
  ///
  /// The dot was enough to tell two rows apart and not enough to be anybody.
  /// This is the same picture they have been chasing round the board all
  /// evening, at a size where it is that animal rather than a smudge of paint.
  static const _art = 34.0;

  /// Gold, silver, bronze. Deliberately fixed rather than themed: a medal that
  /// changes colour with the theme is not a medal.
  static const _medal = <int, Color>{
    1: Color(0xFFD4AF37),
    2: Color(0xFFAFB6BD),
    3: Color(0xFFB07B4F),
  };

  @override
  Widget build(BuildContext context) {
    final badge = medals ? _medal[place] : null;
    final ink = away ? LobbyFlowColors.muted : LobbyFlowColors.ink;
    // Somebody who is not here is the grey character, whatever colour they
    // last wore: between rounds that colour has gone back to the palette and
    // may be on somebody else by now, and mid-round it is only being kept for
    // the game's sake.
    final art = away ? PlayerPalette.away : color;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badge ?? LobbyFlowColors.paper,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$place',
              style: LobbyText.count.copyWith(
                fontSize: 14,
                color: badge == null ? LobbyFlowColors.muted : Colors.black87,
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (art != null) ...[
            PlayerArt.of(art, PlayerArtSlot.topdown).widget(size: _art),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              me ? '${entry.label} (you)' : entry.label,
              overflow: TextOverflow.ellipsis,
              style: LobbyText.label.copyWith(
                color: ink,
                fontWeight: me ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          if (away) ...[
            const Icon(
              Icons.cloud_off,
              size: 14,
              color: LobbyFlowColors.muted,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            '${entry.total}',
            style: LobbyText.title.copyWith(
              color: ink,
              fontSize: 20,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
