import 'package:flutter/material.dart';

import 'ball_drop.dart';

import '../app_controller.dart';
import '../client/client_session.dart' show RoundVerdict;
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
    final theme = Theme.of(context);
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

    return BallDrop(
      child: Scaffold(
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
                    // Whose result this is, before what the result was. The
                    // portrait is the same character this phone has been all
                    // round, so the screen is recognisably *yours* at a glance
                    // across a table — which is the same job the colour does
                    // everywhere else.
                    if (me != null) ...[
                      Center(child: me.face.widget(size: 72)),
                      const SizedBox(height: 12),
                    ],
                    Icon(
                      verdict.celebrate ? Icons.emoji_events : Icons.replay,
                      size: 44,
                      color: verdict.celebrate
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      verdict.headline,
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (title != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    // The game's line for this phone in particular, above the
                    // line everyone gets — "You made 320 points" matters more to
                    // the person holding the phone than "time ran out" does.
                    if (verdict.line != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        verdict.line!,
                        style: theme.textTheme.titleSmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                    if (summary != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        summary,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 18),
                    StandingsCard(
                      scores: host?.scores.view ?? client.scores,
                      meId: client.phoneId,
                      showDeltas: true,
                      offline: awayPhoneIds(controller),
                    ),
                    const SizedBox(height: 20),
                    // The host drives what happens next, and the button no longer
                    // names the game — announcing it here was the same spoiler the
                    // "Up next" card was.
                    if (host != null)
                      FilledButton.icon(
                        onPressed: hasNext
                            ? host.advanceToNextGame
                            : runIsOver
                            ? host.showScoreboard
                            : host.returnToLobby,
                        icon: Icon(
                          hasNext
                              ? Icons.arrow_forward
                              : runIsOver
                              ? Icons.emoji_events
                              : Icons.list,
                        ),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            hasNext
                                ? 'Next game'
                                : runIsOver
                                ? 'Score board'
                                : 'Back to the games',
                          ),
                        ),
                      )
                    else
                      Text(
                        hasNext
                            ? 'Waiting for the host to start the next one…'
                            : runIsOver
                            ? 'Waiting for the host to show the score board…'
                            : 'Waiting for the host to pick the next game…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
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
