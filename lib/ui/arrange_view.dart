import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../host/host_session.dart';
import '../model/arrangement.dart';
import 'metrics_card.dart';
import 'strip_diagram.dart';

/// The table screen: which minigame is next, and where every phone goes.
///
/// Split out from the lobby on purpose. The lobby is about letting people in
/// and never changes; this changes every single round, because each minigame
/// declares the board shape it needs — a slingshot wants a long runway, the
/// ball bin wants a tall well. Rearranging the phones between rounds is the
/// part you feel, so it gets a screen of its own.
class ArrangeView extends StatelessWidget {
  const ArrangeView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;
    final host = controller.host;
    final theme = Theme.of(context);

    final arrangement = host?.game.arrangement ?? client.arrangement;
    final title = host?.game.title ?? client.miniGameTitle ?? 'Next game';
    final tagline = host?.game.tagline ?? client.miniGameTagline ?? '';
    final goal = host?.game.goal ?? client.miniGameGoal ?? '';

    final phones = host != null
        ? [
            for (final p in host.phones)
              DiagramPhone(
                label: p.label,
                widthMm: p.metrics?.widthMm ?? 70,
                heightMm: p.metrics?.heightMm ?? 150,
                isMe: p.phoneId == client.phoneId,
                connected: p.connected,
              ),
          ]
        : [
            for (final p in client.lobbyPhones)
              DiagramPhone(
                label: (p['label'] as String?) ?? '?',
                widthMm: (p['widthMm'] as num?)?.toDouble() ?? 70,
                heightMm: (p['heightMm'] as num?)?.toDouble() ?? 150,
                isMe: p['phoneId'] == client.phoneId,
                connected: (p['connected'] as bool?) ?? true,
              ),
          ];

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Up next', style: theme.textTheme.labelMedium
                                ?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                            Text(title, style: theme.textTheme.headlineSmall),
                          ],
                        ),
                      ),
                      if (host != null)
                        TextButton.icon(
                          onPressed: host.backToLobby,
                          icon: const Icon(Icons.arrow_back, size: 18),
                          label: const Text('Lobby'),
                        )
                      else
                        TextButton(
                          onPressed: controller.leave,
                          child: const Text('Leave'),
                        ),
                    ],
                  ),
                  if (tagline.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(tagline, style: theme.textTheme.bodyMedium),
                  ],
                  if (goal.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      goal,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _ArrangementCard(
                    arrangement: arrangement,
                    phones: phones,
                  ),
                  const SizedBox(height: 14),
                  MetricsCard(
                    metrics: client.metrics,
                    onChanged: client.updateMetrics,
                  ),
                  if (host != null) ...[
                    const SizedBox(height: 14),
                    _PhoneOrderList(
                      host: host,
                      meId: client.phoneId,
                      arrangement: arrangement,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed:
                          host.canPlacePhones ? host.sendPlacement : null,
                      icon: const Icon(Icons.grid_view),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Lay out the board'),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'The host is setting the board up…',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrangementCard extends StatelessWidget {
  const _ArrangementCard({required this.arrangement, required this.phones});

  final Arrangement arrangement;
  final List<DiagramPhone> phones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  arrangement.isHorizontal
                      ? Icons.view_column
                      : Icons.view_stream,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(arrangement.title, style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            ArrangementDiagram(
              phones: phones,
              arrangement: arrangement,
              // A stack needs vertical room; a strip reads fine short and wide.
              extent: arrangement.isHorizontal ? 88 : 150,
            ),
            const SizedBox(height: 12),
            Text(
              arrangement.instruction,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// The list order *is* the physical arrangement, so it has to be editable: the
/// host is not necessarily the phone on the left, or on top.
class _PhoneOrderList extends StatelessWidget {
  const _PhoneOrderList({
    required this.host,
    required this.meId,
    required this.arrangement,
  });

  final HostSession host;
  final String? meId;
  final Arrangement arrangement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phones = host.phones;
    final horizontal = arrangement.isHorizontal;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            for (final (i, p) in phones.indexed)
              ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 13,
                  child: Text('${i + 1}', style: theme.textTheme.labelSmall),
                ),
                title: Row(
                  children: [
                    Text(p.label),
                    if (p.phoneId == meId) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(this phone)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  p.metrics == null
                      ? 'waiting for calibration…'
                      : '${p.metrics!.widthMm.toStringAsFixed(0)} × '
                          '${p.metrics!.heightMm.toStringAsFixed(0)} mm · '
                          'bezel ${p.metrics!.bezelMm.toStringAsFixed(1)} mm · '
                          '${p.link.debugName}',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: horizontal ? 'Move left' : 'Move up',
                      visualDensity: VisualDensity.compact,
                      onPressed: i == 0 ? null : () => host.movePhone(i, -1),
                      icon: Icon(
                        horizontal ? Icons.arrow_back : Icons.arrow_upward,
                        size: 18,
                      ),
                    ),
                    IconButton(
                      tooltip: horizontal ? 'Move right' : 'Move down',
                      visualDensity: VisualDensity.compact,
                      onPressed: i == phones.length - 1
                          ? null
                          : () => host.movePhone(i, 1),
                      icon: Icon(
                        horizontal ? Icons.arrow_forward : Icons.arrow_downward,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
