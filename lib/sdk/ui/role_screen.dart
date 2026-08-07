import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/device_metrics.dart';
import '../model/player_color.dart';
import 'join_sheet.dart';
import 'metrics_card.dart';
import 'theme/app_colors.dart';
import 'theme/app_dimens.dart';
import 'widgets/notice_banner.dart';

/// Pick a role. One app, two jobs: run the world, or be a window onto it.
class RoleScreen extends StatefulWidget {
  const RoleScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<RoleScreen> createState() => _RoleScreenState();
}

class _RoleScreenState extends State<RoleScreen> {
  DeviceMetrics? _metrics;

  /// Whether the surface we are drawing on is wider than it is tall, despite
  /// the portrait lock.
  bool _surfaceIsLandscape = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-measured every time the view changes, not just once. A device that
    // settles into the locked orientation a beat after launch then corrects
    // itself instead of carrying a first guess for the rest of the session.
    _metrics = _detect();
  }

  DeviceMetrics _detect() {
    final view = View.of(context);
    final px = view.physicalSize;

    // The app is locked portrait, so the short edge is the width. Taking the
    // min and max rather than the raw values survives being measured a frame
    // before that lock lands.
    //
    // This describes the *panel*, never the placement. A phone lying on its
    // side in a game's board is still measured portrait here; the turning is
    // the game's business, and travels as `quarterTurns` on its placement.
    _surfaceIsLandscape = px.width > px.height;

    return DeviceMetrics.estimate(
      physicalPx: Size(
        math.min(px.width, px.height),
        math.max(px.width, px.height),
      ),
      devicePixelRatio: view.devicePixelRatio,
      platform: defaultTargetPlatform,
    );
  }

  Future<void> _host() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || !mounted) return;
    await widget.controller.startHost(_metrics!, name: name);
  }

  Future<void> _join() async {
    final request = await Navigator.of(context).push<JoinRequest>(
      MaterialPageRoute(builder: (_) => const JoinSheet()),
    );
    if (request == null || !mounted) return;
    await widget.controller
        .joinHost(request.uri, _metrics!, code: request.code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = _metrics;
    final error = widget.controller.error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _HeroBlobs(),
                  const SizedBox(height: AppSpacing.xl),
                  // Left-aligned, not centred: a 34pt weight-800 line ragged
                  // right reads as a headline, the same line centred reads as
                  // a splash screen.
                  Text(
                    'Lay the phones\ntogether!',
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Each screen is one piece of the board, and every game '
                    'arranges them its own way.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (_surfaceIsLandscape) ...[
                    const NoticeBanner(
                      icon: Icons.screen_rotation,
                      message:
                          'Hold this device upright. It is drawing sideways, '
                          'so its measurements — and its place on the board — '
                          'would be wrong.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (error != null) ...[
                    NoticeBanner(
                      icon: Icons.error_outline,
                      message: error,
                      onDismiss: widget.controller.clearError,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (widget.controller.busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    FilledButton.icon(
                      onPressed: metrics == null ? null : _host,
                      icon: const Icon(Icons.podcasts),
                      label: const Text('Host a game'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // Ink rather than an outline. Joining is not the lesser
                    // action — most people at the table do it — so it gets a
                    // solid button too, just not the accent one.
                    FilledButton.icon(
                      onPressed: metrics == null ? null : _join,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.ink,
                        foregroundColor: AppColors.onInk,
                      ),
                      icon: const Icon(Icons.search),
                      label: const Text('Join a game'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  // Demoted below the buttons. This is a ruler-and-millimetres
                  // form: correct to keep, wrong to make the first thing the
                  // menu is about.
                  if (metrics != null)
                    MetricsCard(
                      metrics: metrics,
                      onChanged: (m) => setState(() => _metrics = m),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Both phones must be on the same WiFi, and that network '
                    'must let devices talk to each other. Guest and public '
                    'networks often block exactly that — if the join hangs, '
                    'use a hotspot from one phone instead.',
                    style: theme.textTheme.bodySmall,
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

/// The band of shapes above the title.
///
/// Flat geometry only — a wedge, a bar, three dots — because it has to be
/// drawn from `Container`s rather than shipped as an image: this app already
/// carries five font files, and a decorative asset that has to look right on
/// every phone density is a worse trade than sixty lines of layout.
///
/// The dots borrow [PlayerPalette], so the one thing the menu says in colour is
/// the same thing the lobby says: these are the people at the table.
class _HeroBlobs extends StatelessWidget {
  const _HeroBlobs();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // A quarter-round wedge — the phones-into-one-board shape, and the
          // single largest area of brand colour in the app.
          Container(
            width: 92,
            height: 92,
            decoration: const BoxDecoration(
              color: AppColors.yellow,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(46),
                topRight: Radius.circular(46),
                bottomLeft: Radius.circular(46),
                bottomRight: Radius.circular(12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 34,
            height: 92,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
          const Spacer(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  _Dot(color: PlayerPalette.green.value, size: 22),
                  const SizedBox(width: 8),
                  _Dot(color: PlayerPalette.blue.value, size: 14),
                ],
              ),
              const SizedBox(height: 10),
              _Dot(color: PlayerPalette.pink.value, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Names the game. This name is what friends look for in their join list, so
/// it is the one thing worth asking before the lobby opens.
class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController(text: 'My board');

  @override
  void initState() {
    super.initState();
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    Navigator.of(context).pop(name.isEmpty ? 'My board' : name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Name your game'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(
              labelText: 'Game name',
              counterText: '',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            // JOIN CODE DISABLED — second sentence was: 'You will get a
            // 5-digit code to let them in.'
            'This is how your friends will spot your game in their list.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Open lobby')),
      ],
    );
  }
}

