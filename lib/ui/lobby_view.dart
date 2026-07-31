import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_controller.dart';
import '../client/client_session.dart';
import '../host/host_session.dart';

/// The connection screen, and only that: the code, the QR, the address, and who
/// has arrived.
///
/// Deliberately says nothing about phone placement. That belongs to the
/// arrangement screen, because it changes with every minigame while this screen
/// never does — you set the room up once and let people in, then decide what to
/// play.
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

    final phoneCount =
        host?.phones.length ?? client.lobbyPhones.length;

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
                    _JoinedPanel(client: client, phoneCount: phoneCount),
                  const SizedBox(height: 14),
                  _WhoIsHere(
                    controller: controller,
                    count: phoneCount,
                  ),
                  if (host != null) ...[
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed:
                          host.canStartArranging ? host.startArranging : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Play'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      host.canStartArranging
                          ? 'Next you will place the phones for '
                              '${host.game.title}.'
                          : 'Waiting for every phone to report its size…',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
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

class _JoinedPanel extends StatelessWidget {
  const _JoinedPanel({required this.client, required this.phoneCount});

  final ClientSession client;
  final int phoneCount;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: ListTile(
      leading: const Icon(Icons.check_circle_outline),
      title: Text(client.gameName ?? 'Connected to the host'),
      subtitle: Text(
        'Waiting for the host to start. $phoneCount phone(s) in.',
      ),
    ),
  );
}

/// Everyone who has made it in. Names only — sizes and ordering are the
/// arrangement screen's business.
class _WhoIsHere extends StatelessWidget {
  const _WhoIsHere({required this.controller, required this.count});

  final AppController controller;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = controller.client!;
    final host = controller.host;

    final entries = host != null
        ? [
            for (final p in host.phones)
              (
                label: p.label,
                me: p.phoneId == client.phoneId,
                ready: p.calibrated,
                connected: p.connected,
              ),
          ]
        : [
            for (final p in client.lobbyPhones)
              (
                label: (p['label'] as String?) ?? '?',
                me: p['phoneId'] == client.phoneId,
                ready: (p['calibrated'] as bool?) ?? false,
                connected: (p['connected'] as bool?) ?? true,
              ),
          ];

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == 1 ? '1 phone here' : '$count phones here',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in entries)
                  Chip(
                    avatar: Icon(
                      !e.connected
                          ? Icons.link_off
                          : e.ready
                              ? Icons.smartphone
                              : Icons.hourglass_empty,
                      size: 16,
                      color: e.connected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                    label: Text(e.me ? '${e.label} (you)' : e.label),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
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
