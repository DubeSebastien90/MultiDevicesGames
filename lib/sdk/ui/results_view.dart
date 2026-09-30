import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../client/client_session.dart' show RoundVerdict;
import 'join_code.dart';
import 'sticker/sticker.dart';
import 'standings_card.dart';

/// The round is over: what happened, and where everyone stands.
///
/// Deliberately nothing else. It used to preview the next game and offer a way
/// out, and both got in the way of the only thing anyone looks at here — who
/// won and why. The host moves the table on; anyone who truly wants out can
/// close the app.
class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;
    final host = controller.host;
    final result = client.result;

    // Deliberately only the *received* result, on the host as much as on a
    // joiner: the host is its own client over loopback, so it gets the same
    // message everyone else does. Reading its own `outcome` object here instead
    // would be a second source for one fact, and every time this codebase has
    // had two of those they have eventually disagreed.
    final verdict =
        result?.verdictFor(client.phoneId) ??
        const RoundVerdict(
          headline: 'Round over',
          line: null,
          celebrate: false,
        );
    // This phone's own player. Null only before anybody has been seated, which
    // a finished round cannot be — but a joiner that arrived late has no seat,
    // and gets the screen without a portrait rather than no screen.
    final me = client.me;

    final summary = result?.summary;
    final title = result?.title;

    // A playlist round chains into the next game; one started from the games
    // list ends here. The host knows directly; a joiner reads it from whether
    // the outcome carried a next game at all.
    //
    // Only ever used to decide *which* button the host gets. What comes next is
    // no longer announced: this screen is for what just happened.
    final hasNext = host != null
        ? host.nextGame != null
        : (result?.hasNext ?? false);

    // Three endings, not two. A game picked off the list ends back at the list;
    // a playlist that has run out of games ends at the standings for the whole
    // run, which is the thing everyone stayed for.
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
              // Whose result this is, before what the result was, and big
              // enough to be the first thing seen.
              //
              // [Player.topdown] rather than [Player.face]: the piece as it was
              // on the board thirty seconds ago is the picture the player has
              // actually been watching, and until the artwork loads — or on a
              // build without it — the portrait slot falls back to a plain
              // shape in their colour, which is a coloured square where a
              // character should be.
              //
              // The verdict hangs off its corner like a sticker slapped on.
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
              // The game's line for this phone in particular, above the line
              // everyone gets — "You made 320 points" matters more to the
              // person holding the phone than "time ran out" does.
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
              // The host drives what happens next, and the button does not name
              // the game — announcing it here was the same spoiler the "Up
              // next" card was. The join code beside it, for somebody whose
              // phone dropped out of the run and no longer finds the game in
              // its join list: a scan takes them back to their seat.
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

/// A small spinner and the reason, for a phone with no button to press — so
/// it does not read as a phone that has frozen.
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

/// Won or did not, as a tilted disc.
///
/// The trophy on green when it went your way, the replay arrow on red when it
/// did not. Red rather than grey because a round you lost still happened, and
/// grey is what an unavailable button looks like.
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
