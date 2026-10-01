import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/device_metrics.dart';
import '../monetization/premium_status.dart';
import '../net/discovery.dart';
import '../net/discovery_stack.dart';
import '../net/host_address.dart';
import '../platform_config.dart';
import 'sticker/sticker.dart';
import 'scan_sheet.dart';
import 'settings_screen.dart';

class JoinRequest {
  const JoinRequest(this.uri, this.code);

  final Uri uri;
  final String code;
}

class JoinSheet extends StatefulWidget {
  const JoinSheet({
    super.key,
    this.seatFingerprint,
    required this.metrics,
    required this.onMetricsChanged,
    required this.premium,
  });

  final String? seatFingerprint;

  final DeviceMetrics metrics;
  final ValueChanged<DeviceMetrics> onMetricsChanged;
  final PremiumStatus premium;

  @override
  State<JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<JoinSheet> {
  final GameFinder _listener = createGameFinder();

  @override
  void initState() {
    super.initState();
    _listener.addListener(_onGames);
    _listener.start();
  }

  void _onGames() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _listener.removeListener(_onGames);
    _listener.dispose();
    super.dispose();
  }

  void _joinDiscovered(GameBeacon beacon) {
    Navigator.of(context).pop(JoinRequest(beacon.uri, ''));
  }

  Future<void> _scan() async {
    final raw = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScanSheet()));
    if (raw == null || !mounted) return;

    final target = parseHostTarget(raw);
    if (target == null) {
      _snack('That QR was not a game address.');
      return;
    }
    Navigator.of(context).pop(JoinRequest(target.uri, target.code ?? ''));
  }

  Future<void> _typeAddress() async {
    final raw = await showStickerSheet<String>(
      context,
      builder: (_) => const _AddressDialog(),
    );
    if (raw == null || !mounted) return;

    final target = parseHostTarget(raw);
    if (target == null) {
      _snack('That is not a game address.');
      return;
    }
    Navigator.of(context).pop(JoinRequest(target.uri, target.code ?? ''));
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          metrics: widget.metrics,
          onMetricsChanged: widget.onMetricsChanged,
          premium: widget.premium,
        ),
      ),
    );
  }

  bool _hasASeatIn(GameBeacon game) {
    final mine = widget.seatFingerprint;
    return mine != null && game.rejoinable.contains(mine);
  }

  void _snack(String text) => showStickerToast(context, text);

  @override
  Widget build(BuildContext context) {
    final games = _listener.games;

    return StickerPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: StickerHeader(
              'Find Lobby',
              onBack: () => Navigator.of(context).pop(),
              trailing: StickerButton(
                width: 52,
                height: 52,
                radius: 16,
                tooltip: 'Settings',
                onTap: _openSettings,
                child: const StIcon(Symbols.settings_rounded, size: 28),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              children: [
                if (games.isEmpty)
                  _Searching(failure: _listener.failure)
                else
                  for (final (i, game) in games.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _GameTile(
                        game: game,
                        tiltDeg: i.isEven ? -1 : 1,
                        mine: _hasASeatIn(game),
                        onTap: game.open || _hasASeatIn(game)
                            ? () => _joinDiscovered(game)
                            : null,
                      ),
                    ),
              ],
            ),
          ),
          if (qrScanSupported || PlatformConfig.showDebugUi)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (qrScanSupported)
                    StickerWideButton(
                      label: 'Scan QR Code',
                      icon: Symbols.qr_code_scanner_rounded,
                      color: St.blue,
                      textColor: St.white,
                      height: 72,
                      fontSize: 26,
                      onTap: _scan,
                    ),
                  if (qrScanSupported && PlatformConfig.showDebugUi)
                    const SizedBox(height: 14),
                  if (PlatformConfig.showDebugUi)
                    StickerWideButton(
                      label: 'Type Address',
                      icon: Symbols.keyboard_rounded,
                      fontSize: 20,
                      onTap: _typeAddress,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.game,
    required this.onTap,
    required this.tiltDeg,
    this.mine = false,
  });

  final bool mine;

  final GameBeacon game;
  final VoidCallback? onTap;
  final double tiltDeg;

  static Color _colorFor(String name) {
    final hash = name.codeUnits.fold<int>(
      0,
      (h, unit) => (h * 31 + unit) & 0x7fffffff,
    );
    return St.tileBands[hash % St.tileBands.length];
  }

  @override
  Widget build(BuildContext context) {
    final locked = !game.open && !mine;

    final players = math.max(1, game.players);
    final fg = locked ? St.ink : St.white;

    return StickerButton(
      height: 76,
      radius: 22,
      shadow: 5,
      tiltDeg: locked ? 0 : tiltDeg,
      color: locked ? const Color(0xFFE4E4E4) : _colorFor(game.name),
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(18, 0, 14, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              game.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: St.display(22, color: fg),
            ),
          ),
          if (!game.open && mine) ...[
            const StickerPill(
              'Join back',
              icon: Symbols.refresh_rounded,
              color: St.white,
              textColor: St.ink,
              size: 14,
              border: 2,
            ),
            const SizedBox(width: 8),
          ],
          StickerPill('$players', icon: Symbols.person_rounded, size: 16),
        ],
      ),
    );
  }
}

class _Searching extends StatefulWidget {
  const _Searching({required this.failure});

  final String? failure;

  @override
  State<_Searching> createState() => _SearchingState();
}

class _SearchingState extends State<_Searching> {
  static const _kDots = 3;

  Timer? _timer;
  int _dots = 1;

  @override
  void initState() {
    super.initState();
    if (widget.failure == null && StickerMotion.loops) {
      _timer = Timer.periodic(const Duration(milliseconds: 450), (_) {
        setState(() => _dots = _dots % _kDots + 1);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failure = widget.failure;
    final big = St.display(26);
    final note = St.body(15, weight: FontWeight.w500, color: St.muted);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 90),
      child: Column(
        children: [
          if (failure == null) ...[
            const Pulse(
              scale: 1.12,
              child: StIcon(Symbols.wifi_find_rounded, size: 56),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text('Searching for lobbies', style: big, maxLines: 1),
                ),
                for (var i = 1; i <= _kDots; i++)
                  Opacity(
                    opacity: i <= _dots ? 1 : 0,
                    child: Text('.', style: big),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Ask your friend to tap “Create a Lobby”.',
              style: note,
              textAlign: TextAlign.center,
            ),
          ] else ...[
            const StickerNotice(
              icon: Symbols.wifi_off_rounded,
              message:
                  'This device cannot search the network. Scan the QR code '
                  'on the host screen instead.',
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? _]) =>
      Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return StickerSheetShell(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Type Address', style: St.display(28))),
                  const SheetCloseButton(),
                ],
              ),
              const SizedBox(height: 16),
              StickerField(
                controller: _controller,
                autofocus: true,
                hintText: '192.168.1.42',
                onSubmitted: _submit,
              ),
              const SizedBox(height: 10),
              Text(
                'The host shows this under its QR code in debug builds.',
                style: St.body(14, weight: FontWeight.w500, color: St.muted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              StickerWideButton(
                label: 'Join',
                icon: Symbols.arrow_forward_rounded,
                color: St.go,
                textColor: St.white,
                onTap: _submit,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
