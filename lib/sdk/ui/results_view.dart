import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../client/client_session.dart' show RoundVerdict;
import 'lobby_flow_style.dart';
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
                  // Whose result this is, before what the result was, and big
                  // enough to be the first thing seen.
                  //
                  // [Player.topdown] rather than [Player.face]: the piece as it
                  // was on the board thirty seconds ago is the picture the
                  // player has actually been watching, and until the artwork
                  // loads — or on a build without it — the portrait slot falls
                  // back to a plain shape in their colour, which is a coloured
                  // square where a character should be.
                  if (me != null) ...[
                    Center(child: me.topdown.widget(size: 168)),
                    const SizedBox(height: 16),
                  ],
                  Center(child: VerdictMark(won: verdict.celebrate)),
                  const SizedBox(height: 14),
                  LobbyTitle(verdict.headline, fontSize: 30),
                  if (title != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: LobbyText.label.copyWith(
                        color: LobbyFlowColors.muted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  // The game's line for this phone in particular, above the
                  // line everyone gets — "You made 320 points" matters more to
                  // the person holding the phone than "time ran out" does.
                  if (verdict.line != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      verdict.line!,
                      style: LobbyText.label,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (summary != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      summary,
                      style: LobbyText.body,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 22),
                  StandingsCard(
                    scores: host?.scores.view ?? client.scores,
                    meId: client.phoneId,
                    colors: playerColors(controller),
                    showDeltas: true,
                    offline: awayPhoneIds(controller),
                  ),
                  const SizedBox(height: 22),
                  // The host drives what happens next, and the button no longer
                  // names the game — announcing it here was the same spoiler the
                  // "Up next" card was.
                  if (host != null)
                    LobbyPillButton(
                      onPressed: hasNext
                          ? host.advanceToNextGame
                          : runIsOver
                          ? host.showScoreboard
                          : host.returnToLobby,
                      icon: hasNext
                          ? Icons.arrow_forward
                          : runIsOver
                          ? Icons.emoji_events
                          : Icons.list,
                      label: hasNext
                          ? 'Next game'
                          : runIsOver
                          ? 'Score board'
                          : 'Back to the games',
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
                    Text(
                      hasNext
                          ? 'Waiting for the host to start the next one…'
                          : runIsOver
                          ? 'Waiting for the host to show the score board…'
                          : 'Waiting for the host to pick the next game…',
                      style: LobbyText.body,
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Won or did not, as a disc.
///
/// The old screen put a bare Material icon here, in the theme's primary colour
/// for a win and its muted grey for anything else — which made losing look like
/// a disabled control. This is the flow's own vocabulary instead: the same
/// coloured plate every button on every other screen is made of, the cup on
/// green when it went your way and the arrow on coral when it did not. Coral
/// rather than grey because a round you lost still happened.
class VerdictMark extends StatelessWidget {
  const VerdictMark({super.key, required this.won});

  final bool won;

  @override
  Widget build(BuildContext context) => LobbyMark(
    icon: won ? Icons.emoji_events : Icons.replay_rounded,
    color: won ? LobbyFlowColors.green : LobbyFlowColors.coral,
  );
}
