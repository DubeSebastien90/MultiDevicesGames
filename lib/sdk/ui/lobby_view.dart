import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_controller.dart';
import '../client/client_session.dart';
import '../host/host_session.dart';
import '../model/player_color.dart';
import '../render/player_art.dart';
import 'game_picker.dart';
import 'lobby_flow_style.dart';
import 'standings_card.dart';
import 'table_notice.dart';

/// The connection screen, and only that: the QR, who has arrived, and — on the
/// host — the button that starts the evening.
///
/// Deliberately says nothing about phone placement. That belongs to the
/// arrangement screen, because it changes with every minigame while this screen
/// never does — you set the room up once and let people in, then decide what to
/// play.
///
/// Dressed in the pre-game flow's own style ([LobbyFlowColors] and friends)
/// rather than the app's [ThemeData], because this is the last screen of that
/// flow: you arrive here straight off the entry screen or the join list, and
/// landing on a differently-dressed screen reads as landing in a different app.
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

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;
    final host = controller.host;

    final seats = _seats(controller);
    final title = host?.name ?? client.sessionName ?? 'Lobby';

    return Scaffold(
      backgroundColor: LobbyFlowColors.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                // The back pill *is* Leave. On every other screen in the flow
                // it undoes the step that got you here, and the step that got
                // you here was opening — or joining — this lobby.
                LobbyHeader(
                  title: title,
                  onBack: controller.leave,
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                ),
                const SizedBox(height: 18),
                if (host != null)
                  _HostPanel(host: host)
                else
                  const _JoinedPanel(),
                const SizedBox(height: 16),
                // The roster used to have a panel of its own, under the QR and
                // above this one — a list of names, then a row of characters
                // with nothing tying the two together. The names have moved on
                // top of the characters they belong to, which is one panel
                // instead of two and one lookup instead of none: the standings
                // need the room the moment somebody scores.
                _ColorPicker(client: client, seats: seats),
                const SizedBox(height: 16),
                StandingsCard(
                  scores: host?.scores.view ?? client.scores,
                  meId: client.phoneId,
                  offline: awayPhoneIds(controller),
                  onReset: host?.resetScores,
                ),
                if (client.warning != null || host?.warning != null) ...[
                  const SizedBox(height: 16),
                  TableNotice(controller: controller),
                ],
                if (host != null) ...[
                  // Debug builds only. Two of the three things that set this
                  // are internal failures — a game's `planBoard` refusing the
                  // table, or its `createSim` throwing — and their text is a
                  // class name and an exception, which is a bug report, not a
                  // message for whoever is hosting games night. The third,
                  // the playlist running out for a shrunken table, is worth
                  // saying but is already said properly: `_layOutAgain` sets
                  // a [TableChange] alongside it and [TableChangeScreen]
                  // takes the whole screen on every phone. So nothing a
                  // player needs is lost by hiding this, and in release they
                  // simply land back in the lobby.
                  if (kDebugMode && host.planError != null) ...[
                    const SizedBox(height: 16),
                    _PlanErrorBanner(
                      message: host.planError!,
                      onDismiss: host.clearPlanError,
                    ),
                  ],
                  const SizedBox(height: 24),
                  // The button says why it will not go, instead of a line of
                  // explanation under a button that has gone gray for reasons
                  // of its own. There is one thing a host can do about it and
                  // the button beneath is where they do it.
                  LobbyPillButton(
                    label: host.canStart
                        ? 'Play'
                        : 'Select at least one playable game',
                    icon: host.canStart ? Icons.play_arrow_rounded : null,
                    background: LobbyFlowColors.green,
                    foreground: LobbyFlowColors.ink,
                    fontSize: host.canStart ? 20 : 16,
                    iconSize: 26,
                    radius: LobbyMetrics.bigRadius,
                    padding: const EdgeInsets.symmetric(
                      vertical: 20,
                      horizontal: 20,
                    ),
                    onPressed: host.canStart ? host.startRound : null,
                  ),
                  const SizedBox(height: 14),
                  // The list used to be spread down the lobby, which put
                  // twelve rows of game between the host and everything else
                  // on this screen — it is a thing you set once and then stop
                  // looking at. Gray, because it is not the button this screen
                  // is about.
                  LobbyPillButton(
                    label: 'Choose Games',
                    icon: Icons.tune,
                    background: LobbyFlowColors.field,
                    foreground: LobbyFlowColors.ink,
                    fontSize: 17,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    onPressed: () =>
                        showGamesSheet(context, host, controller.premium),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The flow's gray rounded panel: a heading with something under it.
///
/// [_Panel.bare] is the same plate with no heading of its own, for a panel that
/// lays its own title out — the host's does, beside the QR rather than above
/// it.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.trailing});

  const _Panel.bare({required this.child})
      : title = null,
        trailing = null;

  final String? title;
  final Widget child;

  /// Sits opposite the heading.
  final Widget? trailing;

  static const _padding = EdgeInsets.fromLTRB(20, 16, 20, 20);

  @override
  Widget build(BuildContext context) {
    final heading = title;

    return Container(
      padding: _padding,
      decoration: BoxDecoration(
        color: LobbyFlowColors.field,
        borderRadius: BorderRadius.circular(20),
      ),
      child: heading == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(heading, style: LobbyText.label)),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
    );
  }
}

/// A game whose `planBoard` produced something unusable. Shown here because
/// this is where the round would have started, and it never did.
///
/// Built only under [kDebugMode] — see the call site for why. Left in the app's
/// error colours rather than the flow's palette on purpose: it is a developer's
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
          Icon(Icons.dashboard_customize_outlined,
              color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'That game could not lay the board out: $message',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: Icon(Icons.close, color: scheme.onErrorContainer, size: 18),
          ),
        ],
      ),
    );
  }
}

/// What a phone that is not the host sees where the QR would be: there is
/// nothing for it to do here but wait, and saying so is the whole panel.
class _JoinedPanel extends StatelessWidget {
  const _JoinedPanel();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      title: 'You are in',
      child: Row(
        children: [
          Icon(Icons.check_circle, color: LobbyFlowColors.ink, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Waiting for the host to start.',
              style: LobbyText.body,
            ),
          ),
        ],
      ),
    );
  }
}

/// The way in, and the only one worth drawing: the QR.
///
/// No address and no join code. Friends on the same WiFi find this game by name
/// in their own join list; the QR is what covers the network that will not let
/// them. Neither of those is a string anybody types, so neither is on screen.
class _HostPanel extends StatelessWidget {
  const _HostPanel({required this.host});

  final HostSession host;

  /// Small enough to sit beside the text, big enough for a camera across a
  /// table to take in one go.
  static const _qrSize = 104.0;

  @override
  Widget build(BuildContext context) {
    final qr = host.qrPayload;
    final failure = host.discoveryFailure != null;

    return _Panel.bare(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The words carry this panel and the QR illustrates them, so the
          // words get the room. Stacked to the left of the code rather than
          // above it: the panel is half as tall that way, which keeps Play on
          // the first screenful on a small phone.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Let them in', style: LobbyText.label),
                const SizedBox(height: 6),
                Text(
                  failure
                      // Worth saying, because the join list they are staring
                      // at is never going to fill in. The QR is the only way
                      // in then, so it is the only thing this offers.
                      ? 'This network will not let the game announce itself. '
                            'Have them scan this code.'
                      // How many are in is counted once, on the picker below.
                      // This panel is about the people who are not here yet.
                      : 'Waiting for your friends…',
                  style: LobbyText.body,
                ),
                // Debug builds only. Nobody is asked to type an address in a
                // shipped build — there is no field for it outside debug — so
                // in release this is a row of digits with no instruction
                // attached, which is a puzzle rather than a fallback. It is
                // here because the join sheet's own Type Address button is,
                // and that button needs something to read off.
                if (kDebugMode) ...[
                  const SizedBox(height: 6),
                  SelectableText(
                    host.address?.toString() ?? 'starting…',
                    style: LobbyText.body.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: LobbyFlowColors.paper,
              borderRadius: BorderRadius.circular(16),
            ),
            child: qr == null
                ? const SizedBox(
                    width: _qrSize,
                    height: _qrSize,
                    child: Center(
                      child: Text('starting…', style: LobbyText.hint),
                    ),
                  )
                : QrImageView(
                    // Address *and* code: scanning proves you were standing
                    // in front of this screen, which is what the code asks
                    // for anyway — so a scan should not demand it twice.
                    data: qr,
                    version: QrVersions.auto,
                    size: _qrSize,
                    backgroundColor: LobbyFlowColors.paper,
                    padding: EdgeInsets.zero,
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
  /// name over that character says so by going pale.
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
          p.color!.id: _Seat(
            label: p.label,
            connected: p.connected,
          ),
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
/// Everyone arrives already wearing one, so this screen is never a gate — it is
/// here for the person who wants to be the frog because they are always the
/// frog. A character somebody else has taken keeps their name over it rather
/// than being hidden, which is what makes this the roster as well as the
/// picker: "who is here" and "who is which animal" are one question at a table,
/// and they were being answered by two panels that could not see each other.
class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.client, required this.seats});

  final ClientSession client;
  final Map<String, _Seat> seats;

  @override
  Widget build(BuildContext context) {
    final mine = client.myColor;

    // Phones that have dropped keep their character but are not at the table,
    // so they are not in the count. It is read as "how many of us are playing".
    final here = seats.values.where((s) => s.connected).length;

    return _Panel(
      title: 'Select your character',
      // Where the colour's name used to sit. The characters say which colour
      // they are better than the word did; what nobody could see was how full
      // the table is, and this is the panel that now knows.
      trailing: Text('$here/${PlayerPalette.size}', style: LobbyText.count),
      child: Wrap(
        spacing: 6,
        runSpacing: 10,
        children: [
          for (final c in PlayerPalette.all)
            _Swatch(
              color: c,
              selected: c.id == mine?.id,
              // Mine is never "taken" from my own point of view.
              owner: c.id == mine?.id ? null : seats[c.id],
              onTap: () => client.pickColor(c),
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
/// the board was theirs. This is the same picture they will be looking for a
/// minute later.
///
/// Until the art loads it is [PlayerArt]'s flat geometry, in the same colour
/// the swatch used to be — so on a platform without it, or in the second
/// before it lands, this is the screen it always was.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.owner,
    required this.onTap,
  });

  final PlayerColor color;
  final bool selected;

  /// Somebody else, or null — either free, or [selected] and therefore yours.
  final _Seat? owner;

  final VoidCallback onTap;

  /// Wide enough for a name to be worth reading, narrow enough that eight of
  /// these still wrap to two rows on a small phone.
  static const _width = 72.0;
  static const _disc = 54.0;

  @override
  Widget build(BuildContext context) {
    final taken = owner != null;

    return Semantics(
      // The colour, still: it is the word people say out loud across a table,
      // and a screen reader has no picture to go on.
      label: owner == null ? color.name : '${color.name}, ${owner!.label}',
      selected: selected,
      button: !taken,
      child: GestureDetector(
        onTap: taken ? null : onTap,
        child: SizedBox(
          width: _width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Always laid out, name or no name: without it the free
              // characters ride up and the row looks broken-toothed.
              SizedBox(
                height: 15,
                child: _Name(owner: owner, selected: selected),
              ),
              const SizedBox(height: 3),
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: _disc,
                height: _disc,
                decoration: BoxDecoration(
                  // A tint of their own colour rather than the flat fill: the
                  // character is the colour now, and a saturated disc behind
                  // it left the two fighting each other. Blended onto white
                  // rather than laid over the panel, so the tint keeps its
                  // colour instead of picking up the gray behind it.
                  color: Color.alphaBlend(
                    color.value.withValues(alpha: taken ? 0.10 : 0.22),
                    LobbyFlowColors.paper,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? LobbyFlowColors.ink : Colors.transparent,
                    width: 3,
                  ),
                ),
                // Faded rather than hidden when somebody else has them: which
                // characters are gone is worth seeing, and an empty circle
                // says less than a greyed-out one.
                child: Opacity(
                  opacity: taken ? 0.45 : 1,
                  child: PlayerArt.of(color, PlayerArtSlot.topdown)
                      .widget(size: 38),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The name over a character: theirs, yours, or nobody's.
class _Name extends StatelessWidget {
  const _Name({required this.owner, required this.selected});

  final _Seat? owner;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    // Yours is the one character here you do not need a label to find — it is
    // the ringed one — so it says so in a word rather than in your own name,
    // which you already know.
    if (selected) {
      return const Text(
        'You',
        style: TextStyle(
          color: LobbyFlowColors.ink,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      );
    }

    final seat = owner;
    if (seat == null) return const SizedBox.shrink();

    return Text(
      seat.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: seat.connected ? LobbyFlowColors.ink : LobbyFlowColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        // A phone that has dropped has not stopped being that character; it
        // has stopped being here, and a struck-through name says that without
        // needing a legend.
        decoration: seat.connected ? null : TextDecoration.lineThrough,
      ),
    );
  }
}
