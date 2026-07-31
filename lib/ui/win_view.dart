import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/arrangement.dart';

/// The round is over. Says what was beaten and what is coming, because the next
/// game needs the phones somewhere else and people need a moment's warning.
class WinView extends StatelessWidget {
  const WinView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = controller.client!;
    final host = controller.host;
    final win = client.win;

    final nextTitle = host?.nextGame.title ?? win?.nextTitle ?? 'Next game';
    final nextTagline = host?.nextGame.tagline ?? win?.nextTagline ?? '';
    final nextArrangement =
        host?.nextGame.arrangement ?? win?.nextArrangement ?? Arrangement.strip;
    final progress = win?.progress;

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
                    Icons.emoji_events,
                    size: 44,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'You win!',
                    style: theme.textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${progress.value} ${progress.label}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 22),
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
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                nextArrangement.isHorizontal
                                    ? Icons.view_column
                                    : Icons.view_stream,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  nextArrangement.instruction,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (host != null)
                    FilledButton.icon(
                      onPressed: host.advanceToNextGame,
                      icon: const Icon(Icons.arrow_forward),
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('Set up $nextTitle'),
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
