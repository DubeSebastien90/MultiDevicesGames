import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_controller.dart';
import '../client/client_session.dart';
import '../host/host_session.dart';
import 'game_picker.dart';
import 'metrics_card.dart';
import 'standings_card.dart';

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
                  const SizedBox(height: 14),
                  StandingsCard(
                    scores: host?.scores.view ?? client.scores,
                    meId: client.phoneId,
                    onReset: host?.resetScores,
                  ),
                  const SizedBox(height: 14),
                  // A phone's physical size belongs here, not on a per-game
                  // screen: it is a property of the phone, and you want it
                  // right before anything starts.
                  MetricsCard(
                    metrics: client.metrics,
                    onChanged: client.updateMetrics,
                  ),
                  if (host != null) ...[
                    if (host.lastAuditSummary != null) ...[
                      const SizedBox(height: 14),
                      _AuditNote(
                        summary: host.lastAuditSummary!,
                        address: host.address?.toString(),
                      ),
                    ],
                    if (host.planError != null) ...[
                      const SizedBox(height: 14),
                      _PlanErrorBanner(
                        message: host.planError!,
                        onDismiss: host.clearPlanError,
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Two ways to play. The button is the whole evening: one
                    // game rolls into the next, forever. The list below is for
                    // when somebody wants a particular one.
                    FilledButton.icon(
                      onPressed: host.canStart ? host.startRound : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Play'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      host.canStart
                          ? 'Starts ${host.upcoming!.manifest.title} and keeps '
                                'going — each win rolls into the next game.'
                          : host.blockedReason!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    GamePicker(
                      offers: host.offers,
                      // Already said above the Play button; no need twice.
                      blockedReason: null,
                      onPick: host.startGame,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Or tap one game to play just that, then come back here.',
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

/// The one-line verdict from the last board that was laid out.
///
/// Host-only, and only after a round has been set up. Says whether the
/// connectors came out as joins or as inward fallbacks, and where to read the
/// full numbers — which is the difference between "a stripe looks wrong" and
/// knowing which measurement caused it.
class _AuditNote extends StatelessWidget {
  const _AuditNote({required this.summary, required this.address});

  final String summary;
  final String? address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final worrying = summary.startsWith('NO joins') || summary.contains('rejected');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: worrying
            ? theme.colorScheme.errorContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                worrying ? Icons.warning_amber : Icons.fact_check_outlined,
                size: 18,
                color: worrying
                    ? theme.colorScheme.onErrorContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text('Last board', style: theme.textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            style: theme.textTheme.bodySmall?.copyWith(
              color: worrying
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (address != null) ...[
            const SizedBox(height: 6),
            SelectableText(
              'Full numbers: open '
              '${address!.replaceFirst("ws://", "http://")} in a browser.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A game whose `planBoard` produced something unusable. Shown here because
/// this is where the round would have started, and it never did.
class _PlanErrorBanner extends StatelessWidget {
  const _PlanErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.dashboard_customize_outlined,
              color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'That game could not lay the board out: $message',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: Icon(Icons.close, color: scheme.onErrorContainer, size: 18),
          ),
        ],
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
      title: Text(client.sessionName ?? 'Connected to the host'),
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
