import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../client/client_session.dart';
import '../host/host_session.dart';
import 'arrange_view.dart';
import 'game_view.dart';
import 'lobby_view.dart';
import 'placement_view.dart';
import 'win_view.dart';

/// Routes on the *client* phase, even on the host.
///
/// The host device is a player: it follows the same connect → calibrate → place
/// → play path as every joiner, and only shows extra host controls along the
/// way. One flow, no special case.
///
/// The one exception is the split between the lobby and the arrangement screen.
/// Both are "connected, not yet placed" as far as a client is concerned, so the
/// host's own phase decides which of the two is on screen — and joiners follow
/// the `phase` field the host broadcasts.
class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;

    switch (client.phase) {
      case ClientPhase.connecting:
        return const _Waiting(message: 'Connecting…');

      case ClientPhase.lobby:
        return _arranging
            ? ArrangeView(controller: controller)
            : LobbyView(controller: controller);

      case ClientPhase.placing:
        return PlacementView(controller: controller);

      case ClientPhase.won:
        return WinView(controller: controller);

      case ClientPhase.playing:
        return GameView(
          // Keyed on the game and the layout so a new round — or a
          // re-calibrated board — rebuilds with a fresh camera rather than
          // reusing a stale one. The game id matters on its own: stacking two
          // phones leaves phone 1 at the same offset it had in the strip.
          key: ValueKey(
            '${client.miniGameId}-${client.phoneId}-'
            '${client.layout?.worldOffsetX}-${client.layout?.worldOffsetY}-'
            '${client.layout?.total}',
          ),
          controller: controller,
        );

      case ClientPhase.rejected:
      case ClientPhase.disconnected:
        return _Problem(
          message: client.message ?? 'Disconnected.',
          onBack: controller.leave,
        );
    }
  }

  /// Is the session past the lobby and on to laying phones out? The host knows
  /// first-hand; a joiner reads the phase the host broadcasts.
  bool get _arranging {
    final host = controller.host;
    if (host != null) return host.phase == HostPhase.arranging;
    return controller.client!.hostPhase == 'arranging';
  }
}

class _Waiting extends StatelessWidget {
  const _Waiting({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 14),
          Text(message),
        ],
      ),
    ),
  );
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, required this.onBack});

  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_tethering_off,
                    size: 34,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: onBack,
                    child: const Text('Back'),
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
