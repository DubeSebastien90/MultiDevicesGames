import 'package:flutter/material.dart';

import '../app_controller.dart';
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

    final won = host?.outcome?.won ?? result?.won ?? true;
    final summary = host?.outcome?.summary ?? result?.summary;
    final title = host?.game?.manifest.title ?? result?.title;

    // A playlist round chains into the next game; one started from the games
    // list ends here. The host knows directly; a joiner reads it from whether
    // the outcome carried a next game at all.
    //
    // Only ever used to decide *which* button the host gets. What comes next is
    // no longer announced: this screen is for what just happened.
    final hasNext =
        host != null ? host.nextGame != null : (result?.hasNext ?? false);

    return Scaffold(
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
                  Icon(
                    won ? Icons.emoji_events : Icons.replay,
                    size: 44,
                    color: won
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    won ? 'You win!' : 'Round over',
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
                  ),
                  const SizedBox(height: 20),
                  // The host drives what happens next, and the button no longer
                  // names the game — announcing it here was the same spoiler the
                  // "Up next" card was.
                  if (host != null)
                    FilledButton.icon(
                      onPressed:
                          hasNext ? host.advanceToNextGame : host.returnToLobby,
                      icon: Icon(hasNext ? Icons.arrow_forward : Icons.list),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          hasNext ? 'Next game' : 'Back to the games',
                        ),
                      ),
                    )
                  else
                    Text(
                      hasNext
                          ? 'Waiting for the host to start the next one…'
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
    );
  }
}
