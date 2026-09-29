import 'package:flutter/material.dart';

import '../score/scoreboard.dart';
import '../model/player_color.dart';
import 'sticker/sticker.dart';
import 'standings_card.dart';

/// Connected, and sitting this one out.
///
/// A phone that comes back mid-round has nowhere to be. The board on the table
/// was compiled without it — there is no slice with its name on, so there is
/// nothing to draw and no instruction to give — and slotting it in would mean
/// asking everybody else to pick up their phone and rearrange the table
/// mid-game. So it waits, and is told plainly that it waits, rather than being
/// dropped on a lobby screen that looks like nothing is happening while five
/// other people play.
///
/// Its seat is not gone: the score is still there, the standings still list it,
/// and the next round lays the board out including it. That is what this screen
/// is for — saying so.
class WaitingRoomView extends StatelessWidget {
  const WaitingRoomView({
    super.key,
    required this.scores,
    required this.meId,
    this.playing,
    this.colors = const {},
    this.offline = const <String>{},
  });

  final ScoreView scores;
  final String? meId;

  /// The round being sat out, when the host has said which.
  final String? playing;

  /// Each phone's character, for the standings underneath.
  final Map<String, PlayerColor?> colors;

  final Set<String> offline;

  @override
  Widget build(BuildContext context) {
    return StickerPage(
      maxWidth: 460,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: StickerSpinner(size: 44)),
              const SizedBox(height: 24),
              Text(
                'Waiting for the minigame to start',
                textAlign: TextAlign.center,
                style: St.display(32, height: 1.05),
              ),
              const SizedBox(height: 10),
              Text(
                'You will join in the next one.',
                textAlign: TextAlign.center,
                style: St.body(16, color: St.muted),
              ),

              // Which round they are sitting out, when the host has said.
              // Otherwise the wait has no shape to it.
              if (playing != null) ...[
                const SizedBox(height: 20),
                Center(
                  child: StickerCard(
                    radius: 999,
                    shadow: 4,
                    tiltDeg: -2,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Text(
                      'Now playing: $playing',
                      style: St.display(18, height: 1),
                    ),
                  ),
                ),
              ],

              // Proof the seat was kept: their name and their score, in the
              // same table everybody else is looking at.
              const SizedBox(height: 26),
              StandingsCard(
                scores: scores,
                meId: meId,
                colors: colors,
                offline: offline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
