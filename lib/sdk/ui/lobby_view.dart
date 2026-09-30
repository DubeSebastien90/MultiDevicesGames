import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../platform_config.dart';
import '../audio/ui_audio.dart';
import '../client/client_session.dart';
import '../host/host_session.dart';
import '../score/scoreboard.dart';
import '../model/player_character.dart';
import '../model/player_color.dart';
import '../render/player_art.dart';
import 'game_picker.dart';
import 'join_code.dart';
import 'standings_card.dart';
import 'sticker/sticker.dart';
import 'table_notice.dart';

/// The connection screen, and only that: the QR, who has arrived, and — on the
/// host — the button that starts the evening.
///
/// Deliberately says nothing about phone placement. That belongs to the
/// arrangement screen, because it changes with every minigame while this screen
/// never does — you set the room up once and let people in, then decide what to
/// play.
///
/// The host advertises the game by name over UDP so friends can find it in
/// their join list without typing anything. The QR is on screen for the same
/// reason it always was — broadcast is the first thing a hostile network drops,
/// and the game has to survive that. The plain IP address used to be here too
/// and is not any more: nobody was ever asked to type one, and a row of digits
/// with no instruction attached is a puzzle, not a fallback.
class LobbyView extends StatelessWidget {
  const LobbyView({super.key, required this.controller});

  final AppController controller;

  /// Below this much height the lobby scrolls as a whole instead of holding
  /// still — see [_build].
  static const _stillHeight = 640.0;

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;
    final host = controller.host;

    final seats = _seats(controller);
    final title = host?.name ?? client.sessionName ?? 'Lobby';

    // Type set at twice its size does not push the bottom of the lobby off the
    // bottom of the phone — it overflows the cards, which are drawn to a size.
    // A third larger is as far as this layout stretches, and past that the
    // words stop growing rather than the Play button leaving.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: _build(context, client, host, seats, title),
    );
  }

  Widget _build(
    BuildContext context,
    ClientSession client,
    HostSession? host,
    Map<String, _Seat> seats,
    String title,
  ) {
    final gap = SizedBox(height: host == null ? 16 : 14);

    final top = <Widget>[
      // The back button *is* Leave. On every other screen it undoes the step
      // that got you here, and the step that got you here was opening — or
      // joining — this lobby.
      StickerHeader(title, size: 26, onBack: controller.leave),
      gap,
      if (host != null) _InviteCard(host: host) else const _StatusCard(),
      gap,
      // The roster and the picker are one card: "who is here" and "who is
      // which animal" are one question at a table.
      _CharacterPicker(client: client, seats: seats, compact: host != null),
      gap,
      if (client.warning != null || host?.warning != null) ...[
        TableNotice(controller: controller),
        gap,
      ],
    ];

    final standings = _Standings(
      scores: host?.scores.view ?? client.scores,
      meId: client.phoneId,
      colors: playerColors(controller),
      offline: awayPhoneIds(controller),
      compact: host != null,
      // Asked about first. The button sits a thumb's width from the character
      // picker on a screen people prod while chatting, and there is no undo
      // behind it: the round deltas are gone the moment the totals are.
      onReset: host == null
          ? null
          : () async {
              if (await confirmResetScores(context)) host.resetScores();
            },
    );

    final bottom = <Widget>[
      if (host != null) ...[
        // Debug builds only. Two of the three things that set this are
        // internal failures — a game's `planBoard` refusing the table, or its
        // `createSim` throwing — and their text is a class name and an
        // exception, which is a bug report, not a message for whoever is
        // hosting games night. The third, the playlist running out for a
        // shrunken table, is already said properly by [TableChangeScreen].
        if (PlatformConfig.showDebugUi && host.planError != null) ...[
          const SizedBox(height: 14),
          _PlanErrorBanner(
            message: host.planError!,
            onDismiss: host.clearPlanError,
          ),
        ],
        const SizedBox(height: 14),
        _HostBar(
          host: host,
          onPickGames: () => showGamesScreen(context, host, controller.premium),
        ),
      ],
    ];

    return Scaffold(
      backgroundColor: St.bg,
      body: StickerBackground(
        shapes: lobbyShapes,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: LayoutBuilder(
                builder: (context, box) {
                  const padding = EdgeInsets.fromLTRB(20, 12, 20, 20);

                  // A screen meant to hold still: everything on it is either
                  // a control or a fact about the table, and both are things
                  // a host looks up mid-sentence. So on any phone with the
                  // room, nothing moves — the standings take what is left and
                  // scroll inside themselves.
                  if (box.maxHeight >= _stillHeight) {
                    return Padding(
                      padding: padding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ...top,
                          Expanded(child: _StandingsSlot(child: standings)),
                          ...bottom,
                        ],
                      ),
                    );
                  }

                  // A phone too short to hold it all — the first iPhone SE,
                  // a small Android, big system type — scrolls instead of
                  // overflowing, with the standings at a height of their own.
                  return SingleChildScrollView(
                    padding: padding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ...top,
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: standings,
                        ),
                        ...bottom,
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A game whose `planBoard` produced something unusable. Shown here because
/// this is where the round would have started, and it never did.
///
/// Built only under [kDebugMode] — see the call site for why. Left in the app's
/// error colours rather than the stickers on purpose: it is a developer's
/// banner, and it should not look like part of the design.
class _PlanErrorBanner extends StatelessWidget {
  const _PlanErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.dashboard_customize_outlined,
            color: scheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'That game could not lay the board out: $message',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          IconButton(
            onPressed: withButtonSound(onDismiss),
            icon: Icon(Icons.close, color: scheme.onErrorContainer, size: 18),
          ),
        ],
      ),
    );
  }
}

/// What a phone that is not the host sees where the QR would be: there is
/// nothing for it to do here but wait, and saying so is the whole card.
class _StatusCard extends StatelessWidget {
  const _StatusCard();

  @override
  Widget build(BuildContext context) => StickerCard(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        Transform.rotate(
          angle: -8 * math.pi / 180,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: St.go,
              shape: BoxShape.circle,
              border: Border.all(color: St.ink, width: 3),
            ),
            child: const Center(
              child: StIcon(Symbols.check_rounded, size: 28, color: St.white),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("You're in!", style: St.display(22, height: 1)),
              const SizedBox(height: 3),
              Row(
                children: [
                  Pulse(
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: St.go,
                        shape: BoxShape.circle,
                        border: Border.all(color: St.ink, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Waiting for the host to start…',
                      style: St.body(14, color: _mutedWarm),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Secondary text on a white card, a shade warmer than [St.muted] on yellow.
const _mutedWarm = Color(0xFF6B5A1E);

/// The way in: a QR the size of a sticker, and the way to make it big.
///
/// No address and no join code. Friends on the same WiFi find this game by name
/// in their own join list; the QR is what covers the network that will not let
/// them. Neither of those is a string anybody types, so neither is on screen.
///
/// The code is never drawn large here. A lobby is read at arm's length by the
/// person holding it, while the scanning happens across a table, in whatever
/// light the room has, which wants the code bigger than this card could ever
/// draw it. So the sticker is a button, and [showJoinCodeSticker] is where the
/// code actually lives.
class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.host});

  final HostSession host;

  @override
  Widget build(BuildContext context) {
    return StickerCard(
      padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Let more in!', style: St.display(22, height: 1)),
                const SizedBox(height: 3),
                Text(_line, style: St.body(14, color: _mutedWarm)),
                ..._debugAddress(),
              ],
            ),
          ),
          const SizedBox(width: 14),
          JoinCodeSticker(host: host),
        ],
      ),
    );
  }

  String get _line {
    if (host.discoveryFailure != null) {
      // Worth saying, because the join list they are staring at is never going
      // to fill in. The QR is the only way in then, so it is the only thing
      // this offers.
      return 'This network hides the game. Have friends scan this code.';
    }
    return 'Friends scan to join the next round';
  }

  /// Debug builds only. Nobody is asked to type an address in a shipped build —
  /// there is no field for it outside debug. It is here because the join
  /// list's own Type Address button is, and that button needs something to
  /// read off.
  List<Widget> _debugAddress() {
    if (!PlatformConfig.showDebugUi) return const [];
    return [
      const SizedBox(height: 4),
      SelectableText(
        host.address?.toString() ?? 'starting…',
        style: St.body(11, color: St.muted).copyWith(fontFamily: 'monospace'),
      ),
    ];
  }
}

/// Play, or why not — and the games list beside it.
///
/// The button says why it will not go, instead of a line of explanation under
/// a button that has gone grey for reasons of its own. There is one thing a
/// host can do about most of those reasons, and the tune button beside it is
/// where they do it.
class _HostBar extends StatelessWidget {
  const _HostBar({required this.host, required this.onPickGames});

  final HostSession host;
  final VoidCallback onPickGames;

  static const _height = 72.0;

  @override
  Widget build(BuildContext context) {
    final noGames = host.chosenGames.isEmpty;

    return SizedBox(
      height: _height + 6,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: host.canStart
                ? StickerButton(
                    height: _height,
                    radius: 24,
                    shadow: 6,
                    color: St.go,
                    onTap: host.startRound,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const StIcon(
                          Symbols.play_arrow_rounded,
                          size: 32,
                          color: St.white,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          // Once anybody has scored, the evening is under way
                          // and this is the next of several rather than the
                          // first.
                          host.scores.isUsed ? 'Next round!' : 'Play',
                          style: St.display(28, color: St.white),
                        ),
                      ],
                    ),
                  )
                : _Locked(
                    label: noGames
                        ? 'Pick at least one game'
                        : 'No game fits this table yet',
                  ),
          ),
          const SizedBox(width: 14),
          // The playlist, down to its icon: a thing you set once and then stop
          // looking at. Beside Play rather than under it because it is the fix
          // for a Play that will not go.
          Stack(
            clipBehavior: Clip.none,
            children: [
              StickerButton(
                width: _height,
                height: _height,
                radius: 24,
                shadow: 6,
                tooltip: 'Games in the run',
                onTap: onPickGames,
                child: const StIcon(Symbols.tune_rounded, size: 34),
              ),
              if (noGames)
                Positioned(
                  top: -10,
                  right: -10,
                  child: IgnorePointer(
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: St.pink,
                        shape: BoxShape.circle,
                        border: Border.all(color: St.ink, width: 3),
                      ),
                      child: Center(
                        child: Text(
                          '!',
                          style: St.display(15, color: St.white, height: 1),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where Play would be: a dashed outline, a padlock, and the reason.
class _Locked extends StatelessWidget {
  const _Locked({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashedOutline(),
    child: Container(
      height: _HostBar._height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0x8CFFFFFF),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const StIcon(Symbols.lock_rounded, size: 22, color: St.muted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: St.body(16, color: St.muted, height: 1.2),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DashedOutline extends CustomPainter {
  static final _paint = Paint()
    ..color = St.ink
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(24),
        ).deflate(1.5),
      );
    for (final metric in outline.computeMetrics()) {
      for (double d = 0; d < metric.length; d += 14) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 8, metric.length)),
          _paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Ask before throwing the evening's scores away, and answer whether to.
///
/// A guard rather than an undo, because there is nothing to undo *to*: the
/// totals and every round's delta go together, and the games they came from
/// are not going to be replayed to get them back.
///
/// Public, and returning the answer rather than doing the deed, so the
/// question can be put to a test without a lobby, a host and a socket behind
/// it. Dismissing it any other way — a tap on the scrim, a route popped from
/// elsewhere — reads as no.
Future<bool> confirmResetScores(BuildContext context) async {
  final sure = await showStickerSheet<bool>(
    context,
    builder: (_) => const _ConfirmResetSheet(),
  );
  return sure == true;
}

class _ConfirmResetSheet extends StatelessWidget {
  const _ConfirmResetSheet();

  @override
  Widget build(BuildContext context) {
    return StickerSheetShell(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reset scores?', style: St.display(28)),
              const SizedBox(height: 8),
              Text(
                'Do you really want to reset all scores on this lobby?',
                style: St.body(16, weight: FontWeight.w500, color: _mutedWarm),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  // Backing out is the default, so it gets the back button
                  // every other screen uses for exactly that.
                  StickerBackButton(
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: StickerButton(
                      height: 52,
                      radius: 18,
                      // Red: the colour for a thing that did not go your way,
                      // and the right one for a button that throws an
                      // evening's scores out.
                      color: St.back,
                      onTap: () => Navigator.of(context).pop(true),
                      child: Text(
                        'Reset',
                        style: St.display(22, color: St.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The room left between the cards and the bottom bar, given to the standings.
///
/// Below [_floor] there is no card worth drawing — a heading and no room for a
/// single name is a worse answer than the space it would take — so it stands
/// down and leaves the room to the cards above.
class _StandingsSlot extends StatelessWidget {
  const _StandingsSlot({required this.child});

  final Widget child;

  /// Roughly a heading and two names. It decides whether to draw at all, not
  /// how tall to draw, so being a few pixels out costs nothing.
  static const _floor = 130.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (!box.maxHeight.isFinite || box.maxHeight < _floor) {
        return const SizedBox.shrink();
      }
      return Align(alignment: Alignment.topCenter, child: child);
    },
  );
}

/// The standings, in the lobby: a purple band, then everybody by score.
///
/// Draws nothing until somebody scores. Some games are co-operative and an
/// all-zero table is noise, so a game that never awards points simply never
/// makes this appear.
///
/// As tall as its rows, up to the room it is given; past that the rows scroll
/// under the band, which never moves.
class _Standings extends StatelessWidget {
  const _Standings({
    required this.scores,
    required this.meId,
    required this.colors,
    required this.offline,
    required this.compact,
    required this.onReset,
  });

  final ScoreView scores;
  final String? meId;
  final Map<String, PlayerColor?> colors;
  final Set<String> offline;
  final bool compact;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    if (!scores.isUsed) return const SizedBox.shrink();
    final ranked = scores.ranked;

    return StickerCard(
      padding: EdgeInsets.zero,
      clip: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: St.ink, width: 3)),
            ),
            child: ColoredBox(
              color: St.premium,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  compact ? 10 : 12,
                  onReset == null ? 18 : 10,
                  compact ? 9 : 11,
                ),
                child: Row(
                  children: [
                    const StIcon(
                      Symbols.trophy_rounded,
                      size: 26,
                      color: St.gold,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Standings',
                        style: St.display(
                          compact ? 21 : 22,
                          color: St.white,
                          height: 1,
                        ),
                      ),
                    ),
                    if (onReset != null)
                      StickerButton(
                        height: 32,
                        radius: 11,
                        shadow: 2,
                        border: 2.5,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        onTap: onReset,
                        child: Text('Reset', style: St.display(15)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Flexible(
            child: Stack(
              children: [
                ListView.separated(
                  shrinkWrap: true,
                  // Inside a page that may itself scroll, on a short phone.
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 18),
                  itemCount: ranked.length,
                  separatorBuilder: (_, _) => SizedBox(height: compact ? 6 : 8),
                  itemBuilder: (_, i) => _StandingRow(
                    place: i + 1,
                    entry: ranked[i],
                    me: ranked[i].phoneId == meId,
                    away: offline.contains(ranked[i].phoneId),
                    color: colors[ranked[i].phoneId],
                    compact: compact,
                    odd: i.isOdd,
                  ),
                ),
                // The last row fades out rather than being cut by the card's
                // edge, which is what says there is more below.
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 26,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00FFFFFF), St.white],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One person's line: where they came, who they are, and what they have.
class _StandingRow extends StatelessWidget {
  const _StandingRow({
    required this.place,
    required this.entry,
    required this.me,
    required this.away,
    required this.color,
    required this.compact,
    required this.odd,
  });

  final int place;
  final ScoreEntry entry;
  final bool me;
  final bool away;
  final PlayerColor? color;
  final bool compact;
  final bool odd;

  static const _podium = [St.gold, St.silver, St.bronze];
  static const _awayText = Color(0xFF999999);

  @override
  Widget build(BuildContext context) {
    // Somebody who is not here is the grey character, whatever colour they
    // last wore: between rounds that colour has gone back to the palette and
    // may be on somebody else by now.
    final art = away ? PlayerPalette.away : color;
    final podium = place <= 3;
    final disc = compact ? 28.0 : 30.0;
    final portrait = compact ? 34.0 : 38.0;

    return Container(
      constraints: BoxConstraints(minHeight: compact ? 48 : 52),
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
      decoration: BoxDecoration(
        color: me && color != null
            ? Color.alphaBlend(
                color!.skinLight.withValues(alpha: .33),
                St.white,
              )
            : (odd ? St.white : const Color(0xFFFAF6E8)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: me ? St.ink : Colors.transparent, width: 3),
      ),
      child: Row(
        children: [
          Container(
            width: disc,
            height: disc,
            decoration: BoxDecoration(
              color: podium ? _podium[place - 1] : St.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: podium ? St.ink : const Color(0x33000000),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                '$place',
                style: St.display(compact ? 14 : 15, height: 1),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox.square(
            dimension: portrait,
            child: art == null
                ? null
                : PlayerArt.of(
                    art,
                    PlayerArtSlot.face,
                  ).widget(size: portrait),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              me ? '${entry.label} (you)' : entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: me
                  ? St.display(18)
                  : St.body(16, color: away ? _awayText : St.ink),
            ),
          ),
          if (away) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const StIcon(
                    Symbols.cloud_off_rounded,
                    size: 14,
                    color: Color(0xFF777777),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'away',
                    style: St.body(
                      11,
                      color: const Color(0xFF777777),
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 40),
            child: Text(
              '${entry.total}',
              textAlign: TextAlign.right,
              style: St.display(
                compact ? 20 : 22,
                color: away ? const Color(0xFFAAAAAA) : St.ink,
                height: 1,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ],
      ),
    );
  }
}

/// Who is holding one of the characters.
class _Seat {
  const _Seat({required this.label, required this.connected});

  final String label;

  /// A phone the session remembers that is not on the wire right now. It keeps
  /// its character — walking away does not hand it to somebody else — and the
  /// name over that character says so by being struck through.
  final bool connected;
}

/// Who holds what, by colour id.
///
/// The host holds the roster directly; every other phone is told the same list
/// in the lobby broadcast, in the same shape. Read once per build and handed
/// down, because it answers two questions on this screen — whose name goes over
/// which character, and how many people are here.
Map<String, _Seat> _seats(AppController controller) {
  final client = controller.client!;
  final host = controller.host;

  if (host != null) {
    return {
      for (final p in host.phones)
        if (p.color != null)
          p.color!.id: _Seat(label: p.label, connected: p.connected),
    };
  }
  return {
    for (final p in client.lobbyPhones)
      if (p['color'] is String)
        p['color'] as String: _Seat(
          label: (p['label'] as String?) ?? '?',
          connected: (p['connected'] as bool?) ?? true,
        ),
  };
}

/// Which character you are, at a table where that is how people tell you apart.
///
/// Everyone arrives already wearing one, so this is never a gate — it is here
/// for the person who wants to be the frog because they are always the frog.
/// A character somebody else has taken keeps their name over it rather than
/// being hidden, which is what makes this the roster as well as the picker.
class _CharacterPicker extends StatelessWidget {
  const _CharacterPicker({
    required this.client,
    required this.seats,
    required this.compact,
  });

  final ClientSession client;
  final Map<String, _Seat> seats;

  /// The host's lobby has a bottom bar to make room for, so it is a touch
  /// tighter.
  final bool compact;

  static const _columns = 4;
  static const _minSide = 48.0;

  @override
  Widget build(BuildContext context) {
    final mine = client.myColor;

    // Phones that have dropped keep their character but are not at the table,
    // so they are not in the count. It is read as "how many of us are playing".
    final here = seats.values.where((s) => s.connected).length;

    final gapX = compact ? 22.0 : 18.0;
    final gapY = compact ? 18.0 : 20.0;
    final inset = compact ? 10.0 : 6.0;

    return StickerCard(
      padding: EdgeInsets.fromLTRB(
        16,
        compact ? 12 : 14,
        16,
        compact ? 14 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pick your bubble',
                  style: St.display(22, height: 1),
                ),
              ),
              StickerPill('$here/${PlayerPalette.size}', size: 16),
            ],
          ),
          // Room above the first row for the name tags, which hang over the
          // top edge of their tile.
          SizedBox(height: compact ? 14 : 16),
          LayoutBuilder(
            builder: (context, box) {
              final room = box.maxWidth - inset * 2;
              // The gaps give first on a narrow phone, so a character is
              // never drawn smaller than [_minSide] to keep the design's
              // spacing.
              final gap = math.max(
                6.0,
                math.min(gapX, (room - _minSide * _columns) / (_columns - 1)),
              );
              final side = (room - gap * (_columns - 1)) / _columns;
              final rows = (PlayerPalette.all.length / _columns).ceil();
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: Column(
                  children: [
                    for (var r = 0; r < rows; r++) ...[
                      if (r > 0) SizedBox(height: gapY),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final c
                              in PlayerPalette.all
                                  .skip(r * _columns)
                                  .take(_columns))
                            _CharacterTile(
                              key: ValueKey('character-${c.id}'),
                              color: c,
                              side: side,
                              radius: compact ? 16 : 18,
                              mine: c.id == mine?.id,
                              // Mine is never "taken" from my own point of view.
                              owner: c.id == mine?.id ? null : seats[c.id],
                              onPick: () => client.pickColor(c),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One character to pick, with the name of whoever has it over its head.
///
/// The character rather than a disc of paint, because the disc was a promise
/// about something nobody had seen yet: a player chose Green in the lobby and
/// then had to find out, once the round started, which of the eight animals on
/// the board was theirs. This is the same character, in the same shades, that
/// they will be looking for a minute later — facing them rather than seen from
/// above, because a picker is read upright and up close, not across a table.
class _CharacterTile extends StatelessWidget {
  const _CharacterTile({
    super.key,
    required this.color,
    required this.side,
    required this.radius,
    required this.mine,
    required this.owner,
    required this.onPick,
  });

  final PlayerColor color;
  final double side;
  final double radius;
  final bool mine;

  /// Somebody else, or null — either free, or [mine].
  final _Seat? owner;

  final VoidCallback onPick;

  static const _turn = Duration(milliseconds: 180);

  void _onTap(BuildContext context) {
    final seat = owner;
    if (seat != null) {
      // Taken is not a dead tile: it says who has it, which is the answer to
      // the question the tap was asking.
      showStickerToast(
        context,
        '${seat.label} already has the ${Cast.of(color).name}!',
      );
      return;
    }
    // No button sound: picking plays the character's own voice instead (see
    // [ClientSession.pickColor]).
    if (!mine) onPick();
  }

  @override
  Widget build(BuildContext context) {
    final seat = owner;
    final taken = seat != null;
    final bg = mine
        ? color.value
        : taken
        ? const Color(0xFFEEEEEE)
        : Color.alphaBlend(color.skinLight.withValues(alpha: .2), St.white);

    return Semantics(
      // The colour, still: it is the word people say out loud across a table,
      // and a screen reader has no picture to go on.
      label: taken ? '${color.name}, ${seat.label}' : color.name,
      selected: mine,
      button: !taken,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTap(context),
        child: AnimatedRotation(
          turns: mine ? -6 / 360 : 0,
          duration: _turn,
          child: AnimatedScale(
            scale: mine ? 1.08 : 1,
            duration: _turn,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: St.quick,
                  width: side,
                  height: side,
                  padding: EdgeInsets.all(side * .08),
                  decoration: St.sticker(
                    color: bg,
                    radius: radius,
                    shadow: mine ? 4 : 0,
                  ),
                  // Faded and grey rather than hidden when somebody else has
                  // it: which characters are gone is worth seeing.
                  child: Opacity(
                    opacity: taken ? .4 : 1,
                    child: ColorFiltered(
                      colorFilter: ColorFilter.matrix(
                        greyscaleMatrix(taken ? 1 : 0),
                      ),
                      child: Center(
                        child: PlayerArt.of(
                          color,
                          PlayerArtSlot.face,
                        ).widget(size: side * .72),
                      ),
                    ),
                  ),
                ),
                if (mine || taken)
                  Positioned(
                    top: -13,
                    left: -8,
                    right: -8,
                    child: Center(
                      child: _Tag(mine: mine, seat: seat),
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

/// "YOU" over your own character, the owner's name over anybody else's.
class _Tag extends StatelessWidget {
  const _Tag({required this.mine, required this.seat});

  final bool mine;
  final _Seat? seat;

  @override
  Widget build(BuildContext context) {
    // A phone that has dropped has not stopped being that character; it has
    // stopped being here, and a struck-through name says that without needing
    // a legend.
    final gone = !mine && seat != null && !seat!.connected;
    return Container(
      constraints: const BoxConstraints(maxWidth: 74),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: mine ? St.ink : const Color(0xFF888888),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: St.ink, width: 2),
      ),
      child: Text(
        mine ? 'YOU' : seat!.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: St.body(10, weight: FontWeight.w700, color: St.white, height: 1)
            .copyWith(
              decoration: gone ? TextDecoration.lineThrough : null,
              decorationColor: St.white,
            ),
      ),
    );
  }
}
