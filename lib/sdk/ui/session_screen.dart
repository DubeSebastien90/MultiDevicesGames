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

/// The theme the games were built under: dark, around a teal seed.
final _gameTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF4ECDC4),
    brightness: Brightness.dark,
  ),
  scaffoldBackgroundColor: const Color(0xFF0B1020),
);

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

    final screen = _screenFor(context, client);

    // Above the phase, not inside one. The wipe covers the finished game and
    // uncovers the score, and those are two different phases — so it has to
    // outlive the switch below rather than live in a branch of it. The key
    // keeps one wipe running across the swap instead of restarting it.
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
        // The NameDrop question belongs to *arriving at* the lobby, which is a
        // phase transition and therefore this screen's business rather than the
        // lobby's. Sitting here, the gate's State is created when the phase
        // becomes lobby and disposed when it stops being lobby, so the check
        // runs once per visit — including the visit after a mid-game
        // interruption reopened the question.
        return NameDropGate(child: LobbyView(controller: controller));

      case ClientPhase.placing:
        // The curtain between the lobby and the first board of a run. It sits
        // in front of the placement screen rather than instead of it: the
        // layout has already arrived and the game's view is loading behind
        // this, so the seconds it takes are the same dead seconds placement
        // was always going to spend.
        if (client.showIntro) {
          return IntroAnimation(
            // This phone's own colour, so the table plays one character in six
            // colours. Known already: the roster arrives with the layout that
            // raised the curtain.
            playerColor: client.me?.color.value,
            onDone: client.introFinished,
          );
        }

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
        // Under the dark theme the games were built with, not the stickers'.
        // The board is drawn on its own dark surface, and the few Material
        // pieces over it — the debug HUD, its slider — were tuned for that.
        return Theme(
          data: _gameTheme,
          child: GameView(
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
          // The host's own totals where they exist, the broadcast copy
          // otherwise — the same choice every standings screen makes.
          scores: controller.host?.scores.view ?? client.scores,
          meId: client.phoneId,
          colors: playerColors(controller),
          offline: awayPhoneIds(controller),
          onBackToLobby: controller.host?.returnToLobby,
        );

      // Two endings, one screen, two headlines: a phone that was turned away
      // never had a connection to lose, and telling it that it lost one sends
      // somebody looking at their wifi over a lobby that was simply full.
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

/// The connection is gone, or was never granted.
///
/// Dressed like the rest of the app rather than like an error dialog: a red
/// mark, the reason in plain words, and a way back. Red because this is the
/// one screen you cannot carry on from — it is the back button's colour, and
/// back is the only thing left.
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
                // What the host actually said, under the headline rather than
                // instead of it: 'Lobby is full' is the useful half, and a
                // headline alone is not enough to act on.
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
