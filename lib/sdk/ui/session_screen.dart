import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../client/client_session.dart';
import 'game_view.dart';
import 'sticker/sticker.dart';
import 'lobby_view.dart';
import 'name_drop_notice.dart';
import 'intro_animation.dart';
import 'ball_wipe.dart';
import 'placement_view.dart';
import 'results_view.dart';
import 'scoreboard_view.dart';
import 'standings_card.dart';
import 'table_change_screen.dart';
import 'waiting_room_view.dart';

final _gameTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4ECDC4),
    brightness: Brightness.dark,
  ),
  scaffoldBackgroundColor: const Color(0xFF0B1020),
);

class SessionScreen extends StatelessWidget {
  const SessionScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;

    final change = controller.host?.tableChange ?? client.tableChange;
    if (change != null) {
      final host = controller.host;
      return TableChangeScreen(
        change: change,
        onDismiss: host == null
            ? null
            : (change.carriesOn
                  ? host.dismissTableChange
                  : host.showScoreboard),
      );
    }

    final screen = _screenFor(context, client);

    if (client.wipe != WipePhase.none) {
      return BallWipe(
        key: const ValueKey('round-wipe'),
        onCovered: client.revealResult,
        onDone: client.wipeFinished,
        child: screen,
      );
    }
    return screen;
  }

  Widget _screenFor(BuildContext context, ClientSession client) {
    switch (client.phase) {
      case ClientPhase.connecting:
        return const StickerLoadingScreen(message: 'Connecting…');

      case ClientPhase.lobby:
        return NameDropGate(child: LobbyView(controller: controller));

      case ClientPhase.placing:
        if (client.showIntro) {
          return IntroAnimation(
            playerColor: client.me?.color.value,
            onDone: client.introFinished,
          );
        }

        return PlacementView(
          key: ValueKey(
            '${client.manifest?.id}-${client.phoneId}-'
            '${client.layout?.worldCenterX}-${client.layout?.worldCenterY}',
          ),
          controller: controller,
        );

      case ClientPhase.playing:
        return Theme(
          data: _gameTheme,
          child: GameView(
            key: ValueKey(
              '${client.manifest?.id}-${client.phoneId}-'
              '${client.layout?.worldCenterX}-${client.layout?.worldCenterY}-'
              '${client.layout?.total}',
            ),
            controller: controller,
          ),
        );

      case ClientPhase.waiting:
        return WaitingRoomView(
          scores: client.scores,
          meId: client.phoneId,
          playing: client.manifest?.title,
          colors: playerColors(controller),
          offline: awayPhoneIds(controller),
        );

      case ClientPhase.finished:
        return ResultsView(controller: controller);

      case ClientPhase.scoreboard:
        return ScoreboardView(
          scores: controller.host?.scores.view ?? client.scores,
          meId: client.phoneId,
          colors: playerColors(controller),
          offline: awayPhoneIds(controller),
          onBackToLobby: controller.host?.returnToLobby,
        );

      case ClientPhase.rejected:
        return _Problem(
          title: 'Cannot join',
          message: client.message ?? 'The host turned this phone away.',
          onBack: controller.leave,
        );

      case ClientPhase.disconnected:
        return _Problem(
          title: 'Connection lost',
          message: client.message ?? 'Disconnected.',
          onBack: controller.leave,
        );
    }
  }
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.title,
    required this.message,
    required this.onBack,
  });

  final String title;
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return StickerPage(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(
                  child: StickerMark(
                    icon: Symbols.wifi_off_rounded,
                    color: St.back,
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: St.display(36, height: 1),
                ),
                const SizedBox(height: 14),
                StickerCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: St.body(17, weight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 26),
                StickerWideButton(
                  onTap: onBack,
                  icon: Symbols.arrow_back_rounded,
                  label: 'Back',
                  color: St.back,
                  textColor: St.white,
                  height: 66,
                  fontSize: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
