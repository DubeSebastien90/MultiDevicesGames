import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_controller.dart';
import '../catalog.dart';
import '../client/client_session.dart';
import '../host/host_session.dart';
import '../model/player_color.dart';
import 'game_picker.dart';
import 'standings_card.dart';
import 'table_notice.dart';

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
                  _ColorPicker(client: client),
                  const SizedBox(height: 14),
                  _WhoIsHere(
                    controller: controller,
                    count: phoneCount,
                  ),
                  const SizedBox(height: 14),
                  StandingsCard(
                    scores: host?.scores.view ?? client.scores,
                    meId: client.phoneId,
                    offline: awayPhoneIds(controller),
                    onReset: host?.resetScores,
                  ),
                  if (controller.client?.warning != null ||
                      host?.warning != null) ...[
                    const SizedBox(height: 14),
                    TableNotice(controller: controller),
                  ],
                  if (host != null) ...[
                    if (host.planError != null) ...[
                      const SizedBox(height: 14),
                      _PlanErrorBanner(
                        message: host.planError!,
                        onDismiss: host.clearPlanError,
                      ),
                    ],
                    const SizedBox(height: 16),
                    // One button starts the evening; the one beside it decides
                    // what the evening is. The list used to be spread down the
                    // lobby, which put twelve rows of game between the host and
                    // everything else on this screen — it is a thing you set
                    // once and then stop looking at.
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: host.canStart ? host.startRound : null,
                            icon: const Icon(Icons.play_arrow),
                            label: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Play'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filledTonal(
                          onPressed: () =>
                              showGamesSheet(context, host, controller.premium),
                          icon: const Icon(Icons.settings),
                          tooltip: 'Choose which games are in the run',
                          style: IconButton.styleFrom(
                            // Matched to the Play button beside it: two
                            // controls on one line at two different heights
                            // read as one control and an afterthought.
                            minimumSize: const Size(56, 56),
                          ),
                        ),
                      ],
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
                    const SizedBox(height: 4),
                    Text(
                      _gamesLine(host),
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

/// What Play would actually play, in one line under it.
///
/// Said out loud because the list is now behind a button: a run that quietly
/// plays nine of twelve games, with nothing on screen to say so, is a host
/// wondering where Guacamole went.
///
/// Counts [HostSession.runningOrder] and not the ticks. A game the table is the
/// wrong size for is not in the run no matter how it is ticked, and "all 12
/// games are in the run" over a table of two that can play three of them is the
/// same lie by a longer route.
String _gamesLine(HostSession host) {
  final running = host.runningOrder;
  final total = GameCatalog.playlist.length;
  if (running.isEmpty) return 'No games are in the run.';
  if (running.length == 1) return 'Only ${running.single.manifest.title}.';
  if (running.length == total) return 'All $total games are in the run.';
  return '${running.length} of $total games are in the run.';
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

/// Which colour you are, at a table where that is how people tell you apart.
///
/// Everyone arrives already wearing a colour, so this screen is never a gate —
/// it is here for the person who wants to be Green because they are always
/// Green. A taken swatch is shown struck through rather than hidden, because
/// "somebody else has it" and "it does not exist" should not look the same.
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.client});

  final ClientSession client;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = client.myColor;
    final taken = client.takenColorIds;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Your colour', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (mine != null)
                  Text(
                    mine.name,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: mine.value,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in PlayerPalette.all)
                  _Swatch(
                    color: c,
                    selected: c.id == mine?.id,
                    // Mine is never "taken" from my own point of view.
                    taken: taken.contains(c.id) && c.id != mine?.id,
                    onTap: () => client.pickColor(c),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.taken,
    required this.onTap,
  });

  final PlayerColor color;
  final bool selected;
  final bool taken;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      label: color.name,
      selected: selected,
      button: !taken,
      child: GestureDetector(
        onTap: taken ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: taken ? color.value.withValues(alpha: 0.28) : color.value,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 3,
            ),
          ),
          child: taken
              ? Icon(Icons.close, size: 20, color: scheme.onSurfaceVariant)
              : selected
                  ? Icon(Icons.check, size: 22, color: color.onColor)
                  : null,
        ),
      ),
    );
  }
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
                color: p.color,
              ),
          ]
        : [
            for (final p in client.lobbyPhones)
              (
                label: (p['label'] as String?) ?? '?',
                me: p['phoneId'] == client.phoneId,
                ready: (p['calibrated'] as bool?) ?? false,
                connected: (p['connected'] as bool?) ?? true,
                color: PlayerPalette.byId(p['color'] as String?),
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
                      color: !e.connected
                          ? theme.colorScheme.error
                          : e.color?.value ?? theme.colorScheme.primary,
                    ),
                    label: Text(e.me ? '${e.label} (you)' : e.label),
                    // A wash of the colour, not the colour itself: a chip is
                    // read as text, and eight saturated pills would fight the
                    // swatches above for the same job.
                    backgroundColor: e.color?.value.withValues(alpha: 0.16),
                    side: e.color == null
                        ? null
                        : BorderSide(
                            color: e.color!.value.withValues(alpha: 0.5),
                          ),
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
                      // JOIN CODE DISABLED — showing a code nobody is asked for
                      // would just be a puzzle. The QR beside this still works;
                      // it carries the address, which is the part that matters.
                      // const SizedBox(height: 12),
                      // Text(
                      //   'Give them this code',
                      //   style: theme.textTheme.labelMedium?.copyWith(
                      //     color: theme.colorScheme.onSurfaceVariant,
                      //   ),
                      // ),
                      // const SizedBox(height: 2),
                      // SelectableText(
                      //   host.joinCode,
                      //   style: theme.textTheme.displaySmall?.copyWith(
                      //     fontFamily: 'monospace',
                      //     letterSpacing: 8,
                      //     fontWeight: FontWeight.w600,
                      //     color: theme.colorScheme.primary,
                      //   ),
                      // ),
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
