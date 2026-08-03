import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../client/client_session.dart';
import 'game_view.dart';
import 'lobby_view.dart';
import 'placement_view.dart';
import 'results_view.dart';

/// Routes on the *client* phase, even on the host.
///
/// The host device is a player: it follows the same connect → calibrate →
/// place → play path as every joiner, and only shows extra host controls along
/// the way. One flow, no special case.
///
/// There are four states, not five. Choosing a game runs its `planBoard`,
/// compiles the board and builds the renderer in one go, so there is nothing to
/// review between the lobby and being told where to stand.
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
        return LobbyView(controller: controller);

      case ClientPhase.placing:
        return PlacementView(controller: controller);

      case ClientPhase.playing:
        return GameView(
          // Keyed on the game and the layout so a new round — or a
          // re-calibrated board — rebuilds with a fresh camera rather than
          // reusing a stale one. The game id matters on its own: stacking two
          // phones can leave phone 1 at the same offset it had in a row.
          key: ValueKey(
            '${client.manifest?.id}-${client.phoneId}-'
            '${client.layout?.worldOffsetX}-${client.layout?.worldOffsetY}-'
            '${client.layout?.total}',
          ),
          controller: controller,
        );

      case ClientPhase.finished:
        return ResultsView(controller: controller);

      case ClientPhase.rejected:
      case ClientPhase.disconnected:
        return _Problem(
          message: client.message ?? 'Disconnected.',
          onBack: controller.leave,
        );
    }
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
                  FilledButton(onPressed: onBack, child: const Text('Back')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
