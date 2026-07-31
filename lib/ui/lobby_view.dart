import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_controller.dart';
import '../host/host_session.dart';
import 'metrics_card.dart';
import 'strip_diagram.dart';

/// Step 1 of the build order, as a screen: get phones talking to each other.
///
/// The host advertises the game by name over UDP so friends can find it without
/// typing anything, and gates entry on a 5-digit code so a stranger who sees
/// the name still cannot walk in. The QR (which carries address *and* code) and
/// the plain address are always on screen too — broadcast is the first thing a
/// hostile network drops, and the game has to survive that.
class LobbyView extends StatelessWidget {
  const LobbyView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;
    final host = controller.host;
    final theme = Theme.of(context);

    final phones = host != null
        ? [
            for (final p in host.phones)
              StripPhone(
                label: p.label,
                widthMm: p.metrics?.widthMm ?? 70,
                heightMm: p.metrics?.heightMm ?? 150,
                isMe: p.phoneId == client.phoneId,
                connected: p.connected,
              ),
          ]
        : [
            for (final p in client.lobbyPhones)
              StripPhone(
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
                        child: Text(
                          host != null ? 'Hosting' : 'Joined',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      Text(
                        client.phoneId ?? '…',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: controller.leave,
                        child: const Text('Leave'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (host != null)
                    _HostPanel(host: host)
                  else
                    Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        leading: const Icon(Icons.check_circle_outline),
                        title: const Text('Connected to the host'),
                        subtitle: Text(
                          'Waiting for the host to lay out the board. '
                          '${phones.length} phone(s) in.',
                        ),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text('Planned arrangement', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 6),
                  StripDiagram(phones: phones),
                  const SizedBox(height: 6),
                  Text(
                    'Left to right, top edges aligned.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  MetricsCard(
                    metrics: client.metrics,
                    onChanged: client.updateMetrics,
                  ),
                  if (host != null) ...[
                    const SizedBox(height: 14),
                    _PhoneOrderList(host: host, meId: client.phoneId),
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

class _HostPanel extends StatelessWidget {
  const _HostPanel({required this.host});

  final HostSession host;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final address = host.address?.toString() ?? 'starting…';
    final qr = host.qrPayload;
    final waiting = host.phones.where((p) => p.connected).length < 2;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(host.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        waiting
                            ? 'Waiting for your friends…'
                            : '${host.phones.length} phones in.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Give them this code',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        host.joinCode,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontFamily: 'monospace',
                          letterSpacing: 8,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (qr != null)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: QrImageView(
                      // Address *and* code: scanning proves you were standing
                      // in front of this screen, which is what the code asks
                      // for anyway — so a scan should not demand it twice.
                      data: qr,
                      version: QrVersions.auto,
                      size: 112,
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              host.discoveryFailure == null
                  ? 'Your game shows up under “${host.name}” when they tap '
                        '“Join a game”. They can also scan the QR, or type '
                        '$address.'
                  : 'This network will not let the game announce itself. Have '
                        'them scan the QR, or type $address.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The list order *is* the physical arrangement, so it has to be editable: the
/// host is not necessarily the phone on the left.
class _PhoneOrderList extends StatelessWidget {
  const _PhoneOrderList({required this.host, required this.meId});

  final HostSession host;
  final String? meId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phones = host.phones;

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
                      tooltip: 'Move left',
                      visualDensity: VisualDensity.compact,
                      onPressed: i == 0 ? null : () => host.movePhone(i, -1),
                      icon: const Icon(Icons.arrow_back, size: 18),
                    ),
                    IconButton(
                      tooltip: 'Move right',
                      visualDensity: VisualDensity.compact,
                      onPressed: i == phones.length - 1
                          ? null
                          : () => host.movePhone(i, 1),
                      icon: const Icon(Icons.arrow_forward, size: 18),
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
