import 'package:flutter/material.dart';

import '../score/scoreboard.dart';
import '../model/player_color.dart';
import 'sticker/sticker.dart';
import 'standings_card.dart';

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

  final String? playing;

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
