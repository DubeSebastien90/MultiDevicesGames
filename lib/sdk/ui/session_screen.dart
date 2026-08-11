import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../client/client_session.dart';
import 'game_view.dart';
import 'lobby_view.dart';
import 'placement_view.dart';
import 'results_view.dart';
import 'scoreboard_view.dart';
import 'standings_card.dart';
import 'table_change_screen.dart';
import 'waiting_room_view.dart';

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

    // Ahead of the phase, not inside one. The table changing shape is a thing
    // that happens *to* whichever screen this phone is on: the placement screen
    // usually, the lobby when the playlist has run out. Routing it here means
    // neither screen has to know about it, and neither can end up showing a
    // stale board behind a message saying the board has changed.
    final change = controller.host?.tableChange ?? client.tableChange;
    if (change != null) {
      final host = controller.host;
      return TableChangeScreen(
        change: change,
        // Two different endings need two different buttons. Carrying on is only
        // an acknowledgement — the next round is already laid out and waiting.
        // A dead end is not: nothing left in the list can be played by the
        // phones that are here, so the run is over, and what a finished run owes
        // the table is its final standings. The scoreboard's own way out is the
        // lobby, which winds the playlist back to the top — so the screen this
        // eventually lands on is one where Play works again.
        onDismiss: host == null
            ? null
            : (change.carriesOn
                ? host.dismissTableChange
                : host.showScoreboard),
      );
    }

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
        return PlacementView(
          key: ValueKey(
            '${client.manifest?.id}-${client.phoneId}-'
            '${client.layout?.worldCenterX}-${client.layout?.worldCenterY}',
          ),
          controller: controller,
        );

      case ClientPhase.playing:
        return GameView(
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
        );

      case ClientPhase.waiting:
        return WaitingRoomView(
          scores: client.scores,
          meId: client.phoneId,
          playing: client.manifest?.title,
          offline: awayPhoneIds(controller),
        );

      case ClientPhase.finished:
        return ResultsView(controller: controller);

      case ClientPhase.scoreboard:
        return ScoreboardView(
          // The host's own totals where they exist, the broadcast copy
          // otherwise — the same choice every standings screen makes.
          scores: controller.host?.scores.view ?? client.scores,
          meId: client.phoneId,
          colors: playerColors(controller),
          offline: awayPhoneIds(controller),
          onBackToLobby: controller.host?.returnToLobby,
        );

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
