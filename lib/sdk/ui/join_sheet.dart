import 'package:flutter/material.dart';
// JOIN CODE DISABLED — the keypad's digits-only formatter lived here.
// import 'package:flutter/services.dart';

import '../net/discovery.dart';
import '../net/host_address.dart';
import 'scan_sheet.dart';

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
  const JoinSheet({super.key});

  @override
  State<JoinSheet> createState() => _JoinSheetState();
}

class _JoinSheetState extends State<JoinSheet> {
  final _listener = DiscoveryListener();

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

  Future<void> _typeAddress() async {
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => const _AddressDialog(),
    );
    if (raw == null || raw.trim().isEmpty || !mounted) return;

    final target = parseHostTarget(raw);
    if (target == null) {
      _snack('Could not read "$raw" as an address.');
      return;
    }
    // JOIN CODE DISABLED
    Navigator.of(context).pop(JoinRequest(target.uri, target.code ?? ''));

    // final code = target.code ?? await _askForCode(null);
    // if (code == null || !mounted) return;
    // Navigator.of(context).pop(JoinRequest(target.uri, code));
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
    final theme = Theme.of(context);
    final games = _listener.games;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a game'),
        actions: [
          IconButton(
            tooltip: 'Look again',
            onPressed: () => setState(_listener.refresh),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (games.isEmpty)
                  _Searching(failure: _listener.failure)
                else
                  for (final game in games)
                    _GameTile(
                      game: game,
                      onTap: game.open ? () => _joinDiscovered(game) : null,
                    ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (qrScanSupported) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _scan,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: const Text('Scan QR'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _typeAddress,
                        icon: const Icon(Icons.keyboard),
                        label: const Text('Type address'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Games show up on their own when both phones are on the same '
                  'WiFi. If yours is missing, the network is probably blocking '
                  'device-to-device traffic — scan the QR on the host screen, '
                  'or type its address.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
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
  const _GameTile({required this.game, required this.onTap});

  final GameBeacon game;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final players = game.players == 1 ? '1 phone' : '${game.players} phones';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: game.open
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          child: Icon(
            game.open ? Icons.videogame_asset : Icons.lock_clock,
            size: 20,
            color: game.open
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        title: Text(game.name),
        subtitle: Text(
          game.open ? '$players in · tap to join' : '$players · already started',
          style: theme.textTheme.bodySmall,
        ),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _Searching extends StatelessWidget {
  const _Searching({required this.failure});

  final String? failure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: [
          if (failure == null) ...[
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 14),
            Text(
              'Looking for games nearby…',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Ask your friend to tap “Host a game”.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
              'Use the QR or the address instead.',
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

/// The typed-address fallback, unchanged in spirit from v1.
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Host address'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.url,
        onSubmitted: (v) => Navigator.of(context).pop(v),
        decoration: const InputDecoration(
          hintText: '192.168.1.42:8080',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Next'),
        ),
      ],
    );
  }
}
