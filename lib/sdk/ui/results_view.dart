import 'package:flutter/material.dart';

import '../app_controller.dart';
import 'standings_card.dart';

/// The round is over. Says what happened, where everyone stands, and what is
/// coming — because the next game needs the phones somewhere else and people
/// deserve a moment's warning.
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
    final next = host?.nextGame?.manifest;
    final nextTitle = next?.title ?? result?.nextTitle;
    final nextTagline = next?.tagline ?? result?.nextTagline ?? '';
    final nextInstruction = result?.nextInstruction ?? '';

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
                  if (nextTitle != null) ...[
                    const SizedBox(height: 18),
                    _UpNext(
                      title: nextTitle,
                      tagline: nextTagline,
                      instruction: nextInstruction,
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (host != null)
                    FilledButton.icon(
                      onPressed: nextTitle == null
                          ? host.returnToLobby
                          : host.advanceToNextGame,
                      icon: Icon(
                        nextTitle == null ? Icons.list : Icons.arrow_forward,
                      ),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          nextTitle == null
                              ? 'Back to the games'
                              : 'Set up $nextTitle',
                        ),
                      ),
                    )
                  else
                    Text(
                      nextTitle == null
                          ? 'Waiting for the host to pick the next game…'
                          : 'Waiting for the host to start the next one…',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: controller.leave,
                    child: const Text('Leave'),
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

/// What the playlist serves up next, and how to rearrange for it.
///
/// Absent entirely on a one-off round, which is what makes the two ways of
/// playing feel different: the playlist tells you to pick your phone up again,
/// the games list hands you back the menu.
class _UpNext extends StatelessWidget {
  const _UpNext({
    required this.title,
    required this.tagline,
    required this.instruction,
  });

  final String title;
  final String tagline;
  final String instruction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              'Up next',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(title, style: theme.textTheme.titleLarge),
            if (tagline.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                tagline,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            if (instruction.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                instruction,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
