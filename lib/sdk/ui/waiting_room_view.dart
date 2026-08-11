import 'package:flutter/material.dart';

import '../score/scoreboard.dart';
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
    this.offline = const <String>{},
  });

  final ScoreView scores;
  final String? meId;

  /// The round being sat out, when the host has said which.
  final String? playing;
  final Set<String> offline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Waiting for the minigame to start',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'You will join in the next one.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),

                    // Which round they are sitting out, when the host has said.
                    // Otherwise the wait has no shape to it.
                    if (playing != null) ...[
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Now playing: $playing',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],

                    // Proof the seat was kept: their name and their score, in
                    // the same table everybody else is looking at.
                    const SizedBox(height: 26),
                    StandingsCard(scores: scores, meId: meId, offline: offline),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
