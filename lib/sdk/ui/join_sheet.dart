import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// JOIN CODE DISABLED — the keypad's digits-only formatter lived here.
// import 'package:flutter/services.dart';

import '../model/device_metrics.dart';
import '../monetization/premium_status.dart';
import '../net/discovery.dart';
import '../net/discovery_stack.dart';
import '../net/host_address.dart';
import '../platform_config.dart';
import 'sticker/sticker.dart';
import 'scan_sheet.dart';
import 'settings_screen.dart';

/// Everything needed to get into a game: where, and the code to prove you were
/// asked along.
///
/// JOIN CODE DISABLED — [code] is now always empty from this sheet, and the
/// host ignores it. The field stays so the plumbing survives.
class JoinRequest {
  const JoinRequest(this.uri, this.code);

  final Uri uri;
  final String code;
}

/// Browse the games being hosted on this WiFi and tap one to join.
///
/// JOIN CODE DISABLED — there used to be a keypad step after picking a game.
///
/// Three ways in, all present on every device and in this order of ease:
/// pick from the list, scan the host's QR, or type the address. The list is the
/// happy path; the other two exist because broadcast is exactly the kind of
/// traffic that guest networks and locked-down platforms drop, and the game has
/// to stay playable when that happens.
class JoinSheet extends StatefulWidget {
  const JoinSheet({
    super.key,
    this.seatFingerprint,
    required this.metrics,
    required this.onMetricsChanged,
    required this.premium,
  });

  /// How this phone appears in a host's list of empty seats, so a game already
  /// under way can tell whether it is still this phone's game.
  final String? seatFingerprint;

  /// Carried only so the gear in the header can open settings from here.
  final DeviceMetrics metrics;
  final ValueChanged<DeviceMetrics> onMetricsChanged;
  final PremiumStatus premium;

  @override
  State<JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<JoinSheet> {
  // Typed as the contract, built by the factory: this sheet only ever reads
  // `games`, `failure` and `refresh`, so how many transports are behind it —
  // one on Android, two on iOS — is not its business.
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

  /// A game picked off the list. Tapping it is the whole join.
  // JOIN CODE DISABLED — was: ask for the code, then pop with it.
  void _joinDiscovered(GameBeacon beacon) {
    Navigator.of(context).pop(JoinRequest(beacon.uri, ''));

    // final code = await _askForCode(beacon.name);
    // if (code == null || !mounted) return;
    // Navigator.of(context).pop(JoinRequest(beacon.uri, code));
  }

  /// The QR carries the code in its fragment, so a scan needs no keypad.
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
    // JOIN CODE DISABLED — the fragment is still parsed, just not required.
    Navigator.of(context).pop(JoinRequest(target.uri, target.code ?? ''));

    // final code = target.code ?? await _askForCode(null);
    // if (code == null || !mounted) return;
    // Navigator.of(context).pop(JoinRequest(target.uri, code));
  }

  /// The address typed by hand — debug builds only.
  ///
  /// The way back in on a platform with no scanner, which on this project means
  /// Windows: [mobile_scanner] has no implementation there, so [qrScanSupported]
  /// is false and the button beside this one is not built. It is not shipped
  /// because nothing in a release build shows an address to type — the host's
  /// lobby prints one only under [kDebugMode] too.
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
    // JOIN CODE DISABLED — a typed address carries no code, and the host is
    // not asking for one.
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

  /// Is one of the empty seats in [game] this phone's?
  bool _hasASeatIn(GameBeacon game) {
    final mine = widget.seatFingerprint;
    return mine != null && game.rejoinable.contains(mine);
  }

  // JOIN CODE DISABLED
  // Future<String?> _askForCode(String? gameName) => showDialog<String>(
  //   context: context,
  //   builder: (_) => _CodeDialog(gameName: gameName),
  // );

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
                        // A game under way is worth tapping only if this phone
                        // left a seat in it. Letting anyone tap meant strangers
                        // walked into a rejection screen; refusing everyone
                        // meant somebody whose battery died could not get back
                        // to their own game.
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

/// One game on the network, as a coloured sticker you tap to join.
class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.game,
    required this.onTap,
    required this.tiltDeg,
    this.mine = false,
  });

  /// This phone left a seat in this game and can walk back into it.
  final bool mine;

  final GameBeacon game;
  final VoidCallback? onTap;
  final double tiltDeg;

  /// A game's colour, fixed by its name rather than its place in the list, so
  /// it neither changes as other games come and go nor differs between
  /// phones. Spelled out rather than leaning on [String.hashCode], which
  /// promises nothing across runs or platforms.
  static Color _colorFor(String name) {
    final hash = name.codeUnits.fold<int>(
      0,
      (h, unit) => (h * 31 + unit) & 0x7fffffff,
    );
    return St.tileBands[hash % St.tileBands.length];
  }

  @override
  Widget build(BuildContext context) {
    // A game under way that isn't this phone's cannot be tapped, and says so by
    // going grey rather than by wearing a colour it cannot deliver on.
    final locked = !game.open && !mine;
    // Somebody is hosting it, so somebody is in it — a beacon that says
    // otherwise is stale, not empty.
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
            // All three dots are always laid out; only their opacity changes.
            // The line's width never moves, so it can neither reflow nor
            // shuffle as the animation runs.
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

// JOIN CODE DISABLED — kept whole, block-commented, so bringing the gate back
// is deleting the two `/*` `*/` lines around it.
/*
/// The 5-digit keypad gate.
class _CodeDialog extends StatefulWidget {
  const _CodeDialog({required this.gameName});

  /// Null when we got here by QR or typed address and have no name to show.
  final String? gameName;

  @override
  State<_CodeDialog> createState() => _CodeDialogState();
}

class _CodeDialogState extends State<_CodeDialog> {
  final _controller = TextEditingController();
  bool _valid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final valid = isValidJoinCode(_controller.text);
      if (valid != _valid) setState(() => _valid = valid);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_valid) Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.gameName;

    return AlertDialog(
      title: Text(name == null ? 'Enter the code' : 'Join “$name”'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'The 5 digits shown on the host’s screen.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 5,
            onSubmitted: (_) => _submit(),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 10,
            ),
            decoration: const InputDecoration(
              counterText: '',
              hintText: '00000',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid ? _submit : null,
          child: const Text('Join'),
        ),
      ],
    );
  }
}
*/

/// Type where the host is. Debug builds only — see [_JoinSheetState._typeAddress].
///
/// [parseHostAddress] is forgiving about what goes in here: a bare IP, a
/// `host:port`, or a whole `ws://…` payload all parse, so the field asks for the
/// shortest of those and accepts the rest.
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
