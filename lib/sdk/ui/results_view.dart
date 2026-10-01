import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../client/client_session.dart' show RoundVerdict;
import 'join_code.dart';
import 'sticker/sticker.dart';
import 'standings_card.dart';

class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;
    final host = controller.host;
    final result = client.result;

    final verdict =
        result?.verdictFor(client.phoneId) ??
        const RoundVerdict(
          headline: 'Round over',
          line: null,
          celebrate: false,
        );

    final me = client.me;

    final summary = result?.summary;
    final title = result?.title;

    final hasNext = host != null
        ? host.nextGame != null
        : (result?.hasNext ?? false);

    final runIsOver = host != null
        ? host.runIsOver
        : (result?.runIsOver ?? false);

    return StickerPage(
      maxWidth: 520,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (me != null)
                Center(
                  child: SizedBox.square(
                    dimension: 190,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Center(child: me.topdown.widget(size: 168)),
                        Positioned(
                          right: -6,
                          bottom: -6,
                          child: VerdictMark(won: verdict.celebrate, size: 72),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Center(child: VerdictMark(won: verdict.celebrate)),
              const SizedBox(height: 18),
              Text(
                verdict.headline,
                textAlign: TextAlign.center,
                style: St.display(38, height: 1),
              ),
              if (title != null) ...[
                const SizedBox(height: 6),
                Text(
                  title,
                  style: St.body(17, color: St.muted),
                  textAlign: TextAlign.center,
                ),
              ],
              if (verdict.line != null || summary != null) ...[
                const SizedBox(height: 14),
                StickerCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Column(
                    children: [
                      if (verdict.line != null)
                        Text(
                          verdict.line!,
                          style: St.body(17, weight: FontWeight.w700),
                          textAlign: TextAlign.center,
                        ),
                      if (verdict.line != null && summary != null)
                        const SizedBox(height: 4),
                      if (summary != null)
                        Text(
                          summary,
                          style: St.body(
                            14,
                            weight: FontWeight.w500,
                            color: St.muted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              StandingsCard(
                scores: host?.scores.view ?? client.scores,
                meId: client.phoneId,
                colors: playerColors(controller),
                showDeltas: true,
                offline: awayPhoneIds(controller),
              ),
              const SizedBox(height: 22),
              if (host != null)
                Row(
                  children: [
                    Expanded(
                      child: StickerWideButton(
                        onTap: hasNext
                            ? host.advanceToNextGame
                            : runIsOver
                            ? host.showScoreboard
                            : host.returnToLobby,
                        icon: hasNext
                            ? Symbols.arrow_forward_rounded
                            : runIsOver
                            ? Symbols.trophy_rounded
                            : Symbols.grid_view_rounded,
                        label: hasNext
                            ? 'Next game'
                            : runIsOver
                            ? 'Score board'
                            : 'Back to the games',
                        color: St.go,
                        textColor: St.white,
                        height: 68,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    JoinCodeSticker(host: host),
                  ],
                )
              else
                _WaitingForHost(
                  hasNext
                      ? 'Waiting for the host to start the next one…'
                      : runIsOver
                      ? 'Waiting for the host to show the score board…'
                      : 'Waiting for the host to pick the next game…',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaitingForHost extends StatelessWidget {
  const _WaitingForHost(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const StickerSpinner(size: 18),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          message,
          style: St.body(15, color: St.muted),
          textAlign: TextAlign.center,
        ),
      ),
    ],
  );
}

class VerdictMark extends StatelessWidget {
  const VerdictMark({super.key, required this.won, this.size = 96});

  final bool won;
  final double size;

  @override
  Widget build(BuildContext context) => StickerMark(
    icon: won ? Symbols.trophy_rounded : Symbols.replay_rounded,
    color: won ? St.go : St.back,
    size: size,
  );
}
