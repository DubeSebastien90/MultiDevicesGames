import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../client/client_session.dart';
import 'game_view.dart';
import 'lobby_view.dart';
import 'placement_view.dart';
import 'results_view.dart';
import 'theme/app_theme.dart';

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
        // Keyed per round for the same reason the game below is: Flutter reuses
        // a State across rounds, and this screen's state is "have I confirmed
        // yet". Carried into the next round that answer is both wrong and
        // unchangeable.
        return _onCanvas(
          PlacementView(
            key: ValueKey(
              '${client.manifest?.id}-${client.phoneId}-'
              '${client.layout?.worldCenterX}-${client.layout?.worldCenterY}',
            ),
            controller: controller,
          ),
        );

      case ClientPhase.playing:
        return _onCanvas(
          GameView(
            // Keyed on the game and the layout so a new round — or a
            // re-calibrated board — rebuilds with a fresh camera rather than
            // reusing a stale one. The game id matters on its own: stacking two
            // phones can leave phone 1 at the same offset it had in a row.
            key: ValueKey(
              '${client.manifest?.id}-${client.phoneId}-'
              '${client.layout?.worldCenterX}-${client.layout?.worldCenterY}-'
              '${client.layout?.total}',
            ),
            controller: controller,
          ),
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

  /// The two phases that draw a board rather than a page.
  ///
  /// Both paint their own dark surface and then put theme-coloured text on top
  /// of it — the placement legend reads `onSurfaceVariant`, the hold ring reads
  /// `primary`. Under the app's light theme that legend would be dark grey on
  /// dark navy, which is to say invisible. So the playfield keeps the dark
  /// theme the whole app used to have, and the lobby chrome gets the light one.
  static Widget _onCanvas(Widget child) =>
      Theme(data: AppTheme.dark, child: child);
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
