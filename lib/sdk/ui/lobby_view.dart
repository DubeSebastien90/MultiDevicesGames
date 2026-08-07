import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_controller.dart';
import '../client/client_session.dart';
import '../host/host_session.dart';
import '../model/player_color.dart';
import 'game_picker.dart';
import 'metrics_card.dart';
import 'standings_card.dart';
import 'theme/app_colors.dart';
import 'theme/app_dimens.dart';
import 'widgets/notice_banner.dart';
import 'widgets/section_card.dart';

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
                          style: theme.textTheme.displaySmall,
                        ),
                      ),
                      if (client.phoneId != null) _PhoneBadge(client.phoneId!),
                      const SizedBox(width: AppSpacing.xs),
                      TextButton(
                        onPressed: controller.leave,
                        child: const Text('Leave'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (host != null)
                    _HostPanel(host: host)
                  else
                    _JoinedPanel(client: client, phoneCount: phoneCount),
                  const SizedBox(height: AppSpacing.md),
                  _ColorPicker(client: client),
                  const SizedBox(height: AppSpacing.md),
                  _WhoIsHere(
                    controller: controller,
                    count: phoneCount,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  StandingsCard(
                    scores: host?.scores.view ?? client.scores,
                    meId: client.phoneId,
                    onReset: host?.resetScores,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // A phone's physical size belongs here, not on a per-game
                  // screen: it is a property of the phone, and you want it
                  // right before anything starts.
                  MetricsCard(
                    metrics: client.metrics,
                    onChanged: client.updateMetrics,
                  ),
                  if (host != null) ...[
                    if (host.planError != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      NoticeBanner(
                        icon: Icons.dashboard_customize_outlined,
                        message: 'That game could not lay the board out: '
                            '${host.planError!}',
                        onDismiss: host.clearPlanError,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    // Two ways to play. The button is the whole evening: one
                    // game rolls into the next, forever. The list below is for
                    // when somebody wants a particular one.
                    //
                    // Taller and rounder than any other button in the app,
                    // because it is the last thing anyone taps before the
                    // phones go down on the table.
                    FilledButton.icon(
                      onPressed: host.canStart ? host.startRound : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 62),
                        shape: const StadiumBorder(),
                        textStyle: theme.textTheme.titleMedium,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 26),
                      label: const Text('Play'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      host.canStart
                          ? 'Starts ${host.upcoming!.manifest.title} and keeps '
                                'going — each win rolls into the next game.'
                          : host.blockedReason!,
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    GamePicker(
                      offers: host.offers,
                      // Already said above the Play button; no need twice.
                      blockedReason: null,
                      onPick: host.startGame,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Or tap one game to play just that, then come back here.',
                      style: theme.textTheme.bodySmall,
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

/// Which phone you are, in the host's numbering. Small, because it only
/// matters when two people are comparing screens.
class _PhoneBadge extends StatelessWidget {
  const _PhoneBadge(this.phoneId);

  final String phoneId;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.yellow,
      borderRadius: BorderRadius.circular(AppRadius.pill),
    ),
    child: Text(
      phoneId,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: AppColors.onYellow,
      ),
    ),
  );
}

/// The joiner's counterpart to [_HostPanel]. Ink for the same reason: on this
/// screen, the block that tells you where you are is the one that should be
/// impossible to miss.
class _JoinedPanel extends StatelessWidget {
  const _JoinedPanel({required this.client, required this.phoneCount});

  final ClientSession client;
  final int phoneCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.yellow,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: AppColors.onYellow, size: 24),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.sessionName ?? 'Connected to the host',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppColors.onInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Waiting for the host to start. $phoneCount phone(s) in.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.onInkSoft,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

    return SectionCard(
      title: 'Your colour',
      icon: Icons.palette_outlined,
      accent: mine?.value,
      trailing: mine == null
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: mine.value,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                mine.name,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: mine.onColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
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
    return Semantics(
      label: color.name,
      selected: selected,
      button: !taken,
      child: GestureDetector(
        onTap: taken ? null : onTap,
        // The ring sits *outside* the swatch rather than being a border on it,
        // so selecting a colour does not shrink the colour you just picked —
        // which is the one moment you are looking straight at it.
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? AppColors.ink : Colors.transparent,
              width: 3,
            ),
          ),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: taken ? color.value.withValues(alpha: 0.22) : color.value,
              shape: BoxShape.circle,
            ),
            child: taken
                ? const Icon(Icons.close, size: 20, color: AppColors.inkSoft)
                : selected
                    ? Icon(Icons.check_rounded, size: 24, color: color.onColor)
                    : null,
          ),
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

    return SectionCard(
      title: count == 1 ? '1 phone here' : '$count phones here',
      icon: Icons.groups_outlined,
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
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
                    ? AppColors.danger
                    : e.color?.value ?? AppColors.ink,
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
              labelStyle: theme.textTheme.labelLarge,
              visualDensity: VisualDensity.compact,
            ),
        ],
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

    // The hero block of the lobby, and the only ink card on a white page. It
    // holds the two things a host is asked for — the name friends look for and
    // the QR they scan — so it is the one block that should read from across
    // the table.
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      host.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: AppColors.onInk,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: waiting
                                ? AppColors.yellow
                                : PlayerPalette.green.value,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          waiting
                              ? 'Waiting for your friends…'
                              : '${host.phones.length} phones in.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.onInkSoft,
                          ),
                        ),
                      ],
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
              if (qr != null) ...[
                const SizedBox(width: AppSpacing.md),
                // Stays white on the ink card. A QR is a contrast target
                // before it is a graphic — inverting it to suit the card
                // would stop a good half of scanners reading it.
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                  child: QrImageView(
                    // Address *and* code: scanning proves you were standing
                    // in front of this screen, which is what the code asks
                    // for anyway — so a scan should not demand it twice.
                    data: qr,
                    version: QrVersions.auto,
                    size: 108,
                    backgroundColor: Colors.white,
                    padding: EdgeInsets.zero,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            host.discoveryFailure == null
                ? 'Your game shows up under “${host.name}” when they tap '
                      '“Join a game”. They can also scan the QR, or type '
                      '$address.'
                : 'This network will not let the game announce itself. Have '
                      'them scan the QR, or type $address.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.onInkSoft,
            ),
          ),
        ],
      ),
    );
  }
}
