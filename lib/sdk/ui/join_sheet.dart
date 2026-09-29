import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// JOIN CODE DISABLED — the keypad's digits-only formatter lived here.
// import 'package:flutter/services.dart';

import '../model/device_metrics.dart';
// import '../monetization/premium_status.dart'; // NO-IAP
import '../net/discovery.dart';
import '../net/discovery_stack.dart';
import '../net/host_address.dart';
import '../platform_config.dart';
import 'lobby_flow_style.dart';
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
    // required this.premium, // NO-IAP
  });

  /// How this phone appears in a host's list of empty seats, so a game already
  /// under way can tell whether it is still this phone's game.
  final String? seatFingerprint;

  /// Carried only so the gear in the header can open settings from here.
  final DeviceMetrics metrics;
  final ValueChanged<DeviceMetrics> onMetricsChanged;
  // final PremiumStatus premium; // NO-IAP

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
    final raw = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanSheet()),
    );
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
    final raw = await showDialog<String>(
      context: context,
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
          // premium: widget.premium, // NO-IAP
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

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final games = _listener.games;

    return Scaffold(
      backgroundColor: LobbyFlowColors.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                LobbyHeader(
                  title: 'Find Lobby',
                  onBack: () => Navigator.of(context).pop(),
                  onSettings: _openSettings,
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    children: [
                      if (games.isEmpty)
                        _Searching(failure: _listener.failure)
                      else
                        for (final game in games)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _GameTile(
                              game: game,
                              mine: _hasASeatIn(game),
                              // A game under way is worth tapping only if this
                              // phone left a seat in it. Letting anyone tap
                              // meant strangers walked into a rejection screen;
                              // refusing everyone meant somebody whose battery
                              // died could not get back to their own game.
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
                    child: Row(
                      children: [
                        if (qrScanSupported)
                          Expanded(
                            child: LobbyPillButton.big(
                              label: 'Scan QR Code',
                              icon: Icons.qr_code_2,
                              background: LobbyFlowColors.yellow,
                              onPressed: _scan,
                              padding: const EdgeInsets.symmetric(
                                vertical: 22,
                                horizontal: 16,
                              ),
                            ),
                          ),
                        if (qrScanSupported && PlatformConfig.showDebugUi)
                          const SizedBox(width: 14),
                        if (PlatformConfig.showDebugUi)
                          Expanded(
                            child: LobbyPillButton.big(
                              label: 'Type Address',
                              icon: Icons.keyboard,
                              background: LobbyFlowColors.cyan,
                              onPressed: _typeAddress,
                              padding: const EdgeInsets.symmetric(
                                vertical: 22,
                                horizontal: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.game,
    required this.onTap,
    this.mine = false,
  });

  /// This phone left a seat in this game and can walk back into it.
  final bool mine;

  final GameBeacon game;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // A game under way that isn't this phone's cannot be tapped, and says so by
    // going gray rather than by wearing a colour it cannot deliver on.
    final locked = !game.open && !mine;
    // Somebody is hosting it, so somebody is in it — a beacon that says
    // otherwise is stale, not empty.
    final players = math.max(1, game.players);

    return LobbyCard(
      onTap: onTap,
      dimmed: locked,
      color: locked
          ? LobbyFlowColors.field
          : LobbyFlowColors.colorForLobby(game.name),
      child: Row(
        children: [
          Expanded(
            child: Text(
              game.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: LobbyText.label,
            ),
          ),
          if (!game.open && mine) ...[
            Text(
              'Join Back Lobby',
              style: LobbyText.button.copyWith(fontSize: 12),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.refresh, size: 17, color: LobbyFlowColors.ink),
            const SizedBox(width: 10),
          ],
          Text('$players', style: LobbyText.count),
          const SizedBox(width: 4),
          const Icon(Icons.person, size: 20, color: LobbyFlowColors.ink),
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

const _searchingStyle = TextStyle(
  color: LobbyFlowColors.muted,
  fontSize: 19,
  fontWeight: FontWeight.w800,
);

class _SearchingState extends State<_Searching> {
  static const _kDots = 3;

  Timer? _timer;
  int _dots = 1;

  @override
  void initState() {
    super.initState();
    if (widget.failure == null) {
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
    final theme = Theme.of(context);
    final failure = widget.failure;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 120),
      child: Column(
        children: [
          if (failure == null) ...[
            // All three dots are always laid out; only their opacity changes.
            // The line's width never moves, so it can neither reflow nor
            // shuffle as the animation runs.
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Flexible(
                  child: Text(
                    'Searching for lobbies',
                    style: _searchingStyle,
                    maxLines: 1,
                  ),
                ),
                for (var i = 1; i <= _kDots; i++)
                  Opacity(
                    opacity: i <= _dots ? 1 : 0,
                    child: const Text('.', style: _searchingStyle),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Ask your friend to tap “Create a Lobby”.',
              style: LobbyText.body,
              textAlign: TextAlign.center,
            ),
          ] else ...[
            Icon(Icons.wifi_find, size: 30, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'This device cannot search the network.',
              style: theme.textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Scan the QR code on the host screen instead.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
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
    return Dialog(
      backgroundColor: LobbyFlowColors.paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LobbyTitle('Type Address', fontSize: 22),
            const SizedBox(height: 18),
            LobbyChipField(
              controller: _controller,
              autofocus: true,
              hintText: '192.168.1.42',
              onSubmitted: _submit,
            ),
            const SizedBox(height: 8),
            const Text(
              'The host shows this under its QR code in debug builds.',
              style: LobbyText.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: LobbyPillButton(
                    label: 'Cancel',
                    background: LobbyFlowColors.field,
                    foreground: LobbyFlowColors.ink,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LobbyPillButton(
                    label: 'Join',
                    background: LobbyFlowColors.green,
                    foreground: LobbyFlowColors.ink,
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
