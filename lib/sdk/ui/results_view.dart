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
                    Card(
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
                            Text(nextTitle, style: theme.textTheme.titleLarge),
                            if (nextTagline.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                nextTagline,
                                style: theme.textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                            if (nextInstruction.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Text(
                                nextInstruction,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (host != null)
                    FilledButton.icon(
                      onPressed: host.advanceToNextGame,
                      icon: const Icon(Icons.arrow_forward),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          nextTitle == null
                              ? 'Back to the lobby'
                              : 'Set up $nextTitle',
                        ),
                      ),
                    )
                  else
                    Text(
                      'Waiting for the host to start the next one…',
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
