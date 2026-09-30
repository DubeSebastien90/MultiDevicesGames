import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/player_color.dart';
import '../render/player_art.dart';
import '../score/scoreboard.dart';
import 'sticker/sticker.dart';
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

    return StickerPage(
      maxWidth: 520,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Bob(child: VerdictMark(won: won)),
              ),
              const SizedBox(height: 20),
              Transform.rotate(
                angle: -2 * math.pi / 180,
                child: Text(
                  _headline(scores, meId),
                  textAlign: TextAlign.center,
                  style: St.display(40, height: 1),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Final standings',
                style: St.body(15, color: St.muted).copyWith(letterSpacing: 2),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 22),

              // Deliberately not a [StandingsCard]: that one draws nothing at
              // all until somebody scores, which is right where it sits —
              // beside other things — and wrong here, where it is the whole
              // screen. A co-operative run that ended level still has to show
              // the table its own names.
              StickerCard(
                padding: const EdgeInsets.all(10),
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
                        odd: i.isOdd,
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 26),
              if (onBackToLobby != null)
                StickerWideButton(
                  onTap: onBackToLobby,
                  icon: Symbols.meeting_room_rounded,
                  label: 'Back to lobby',
                  color: St.go,
                  textColor: St.white,
                  height: 68,
                  fontSize: 24,
                )
              else
                // Something to look at, so a phone with no button does not
                // read as a phone that has frozen.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const StickerSpinner(size: 18),
                    const SizedBox(width: 10),
                    Text(
                      'Waiting for the host…',
                      style: St.body(15, color: St.muted),
                    ),
                  ],
                ),
            ],
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
    required this.odd,
  });

  final int place;
  final ScoreEntry entry;
  final bool me;
  final bool away;
  final PlayerColor? color;
  final bool medals;
  final bool odd;

  /// The character, where a ten-pixel dot of their colour used to be — the
  /// same picture they have been chasing round the board all evening.
  static const _art = 38.0;

  /// Gold, silver, bronze. Fixed rather than themed: a medal that changes
  /// colour with the theme is not a medal.
  static const _medal = <int, Color>{1: St.gold, 2: St.silver, 3: St.bronze};

  static const _awayText = Color(0xFF999999);

  @override
  Widget build(BuildContext context) {
    final badge = medals ? _medal[place] : null;
    // Somebody who is not here is the grey character, whatever colour they
    // last wore: between rounds that colour has gone back to the palette and
    // may be on somebody else by now, and mid-round it is only being kept for
    // the game's sake.
    final art = away ? PlayerPalette.away : color;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      constraints: const BoxConstraints(minHeight: 54),
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
      decoration: BoxDecoration(
        color: me && color != null
            ? Color.alphaBlend(
                color!.skinLight.withValues(alpha: .33),
                St.white,
              )
            : (odd ? St.white : const Color(0xFFFAF6E8)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: me ? St.ink : Colors.transparent, width: 3),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: badge ?? St.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: badge == null ? const Color(0x33000000) : St.ink,
                width: 2,
              ),
            ),
            child: Text('$place', style: St.display(16, height: 1)),
          ),
          const SizedBox(width: 10),
          if (art != null) ...[
            PlayerArt.of(art, PlayerArtSlot.topdown).widget(size: _art),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              me ? '${entry.label} (you)' : entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: me
                  ? St.display(18)
                  : St.body(16, color: away ? _awayText : St.ink),
            ),
          ),
          if (away) ...[
            const StIcon(
              Symbols.cloud_off_rounded,
              size: 16,
              color: Color(0xFF777777),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            '${entry.total}',
            style: St.display(
              24,
              color: away ? const Color(0xFFAAAAAA) : St.ink,
              height: 1,
            ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}
