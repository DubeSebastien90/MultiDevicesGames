import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../platform_config.dart';
import '../model/phone_layout.dart';
import '../contract/sim.dart' show PhoneSlice;
import '../layout/board_links.dart';
import 'board_diagram.dart';
import 'hold_to_confirm.dart';
import 'link_palette.dart';
import 'lobby_flow_style.dart';

/// How thick the edge stripes are drawn, in logical pixels.
///
/// The one number this screen is measured in: the stripes are this wide, the
/// inset that keeps them on the glass is half of it, and the gutter the picture
/// keeps from the edges is twice it — so the diagram grows until it is two
/// connectors away from the bands, and no further.
const double kEdgeStripeWidth = 18.0;

/// "Place yourself here" — the picture, the colours, and a ring you hold.
///
/// Stripped to two pieces of information on purpose: the diagram of the board
/// the game compiled, and the legend naming the colours on this phone's edges.
/// Everything that used to be here — title, goal, "phone 2 of 4", a paragraph of
/// instruction — was text people skip while holding a phone in each hand. The
/// diagram says all of it.
///
/// Nothing measures whether the phones are actually where the host thinks they
/// are: confirming is a human promise, not a sensor reading. What this screen can
/// do is make a wrong promise *visible*, which is what the coloured stripes along
/// the real screen edges are for — line yours up with your neighbour's and the
/// board is right.
class PlacementView extends StatelessWidget {
  const PlacementView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;
    final layout = client.layout;

    // No board to show yet. The ring is deliberately not offered before the
    // diagram exists: "Ready" over an empty space asks people to promise they
    // are somewhere they have not been told about.
    if (layout == null || client.slices.isEmpty) {
      return const LobbyLoadingScreen();
    }

    // Confirmation state comes from the lobby list, but *positions* come from
    // the compiled board — join order says nothing about where a game decided to
    // put anybody.
    final confirmedIds = <String>{
      for (final p in client.lobbyPhones)
        if ((p['confirmed'] as bool?) ?? false) p['phoneId'] as String,
    };

    // No cap on the size here: the picture is the screen's whole message, so
    // it takes every pixel the ring and the legend leave it.
    final diagram = BoardDiagram(
      slices: client.slices,
      board: layout.board,
      links: client.allLinks,
      meId: client.phoneId,
      confirmed: confirmedIds,
      maxExtent: null,
    );

    final legend = client.myLinks.isEmpty
        ? null
        : _LinkLegend(
            links: client.myLinks,
            slices: client.slices,
            onPoke: client.poke,
          );

    return Scaffold(
      // Same paper the lobby, the games list and the results are drawn on: this
      // screen sits between them, and a dark screen in the middle of a white
      // flow reads as a different app.
      backgroundColor: LobbyFlowColors.paper,
      // Deliberately not turned: you read your own phone the way you hold it,
      // whatever angle its slot in the board happens to be.
      body: Stack(
        children: [
          // The stripes hug the real glass edges, so this fills the screen.
          Positioned.fill(
            child: CustomPaint(
              painter: _EdgeStripePainter(
                layout: layout,
                links: client.myLinks,
              ),
            ),
          ),

          // The hold target is the whole screen, and now the only thing on it:
          // no button to find, and nothing to hit by accident while your hands
          // are busy holding phones against each other.
          HoldToConfirm(
            confirmed: confirmedIds.contains(client.phoneId),
            onConfirmed: client.confirmPlacement,
            // Two stripe widths of air all round, so a board drawn as large as
            // it can be still never runs under the bands on the glass.
            padding: const EdgeInsets.all(kEdgeStripeWidth * 2),
            content: diagram,
            // Under the ring rather than under the picture, and outside the
            // hold: these are buttons now, and a button inside the hold target
            // would fill the ring every time it was pressed.
            footer: legend,
          ),

          // Debug builds only, and outside the hold target above so reaching
          // for it cannot confirm a position on the way out. Players get out of
          // a round by finishing it or closing the app; this is for whoever is
          // working on the platform and needs to leave twenty times an hour.
          if (PlatformConfig.showDevChrome)
            Positioned(
              right: 4,
              bottom: 4,
              child: SafeArea(
                child: TextButton(
                  onPressed: controller.leave,
                  child: const Text('Leave'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// This phone's edge stripes, hugging the real screen edge.
///
/// Drawn thick and inset just enough to stay on the glass, because the point is
/// to push two phones together and see one continuous band of colour.
class _EdgeStripePainter extends CustomPainter {
  _EdgeStripePainter({required this.layout, required this.links});

  final PhoneLayout layout;

  /// The most actionable thing on the screen: line the colours up with your
  /// neighbours' and the board is right.
  final List<EdgeMarker> links;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = LobbyFlowColors.paper);

    /// Where a world point lands on this screen, turn included.
    Offset toScreen(double wx, double wy) {
      final px = layout.worldToPhysicalPx(wx, wy);
      final dpr = layout.devicePixelRatio;
      return Offset(px.x / dpr, px.y / dpr);
    }

    // Twice the old width. A band you are asked to line up with your
    // neighbour's across a millimetre of bezel wants to be seen from arm's
    // length, and a thin line reads as decoration rather than an instruction.
    final stripe = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = kEdgeStripeWidth
      ..strokeCap = StrokeCap.round;

    for (final link in links) {
      final a = toScreen(link.x1, link.y1);
      final b = toScreen(link.x2, link.y2);
      // Pull the line a few pixels inside the panel, or half its width falls
      // off the glass.
      final inset = _towardCentre(a, b, size, kEdgeStripeWidth / 2);
      stripe.color = link.isJoin
          ? LinkPalette.of(link.colorIndex)
          : LinkPalette.inward;
      canvas.drawLine(a + inset, b + inset, stripe);
    }
  }

  /// A small nudge from a screen-edge segment toward the middle of the screen,
  /// so a stroke centred on the very edge is not half invisible.
  Offset _towardCentre(Offset a, Offset b, Size size, double by) {
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final to = Offset(size.width / 2 - mid.dx, size.height / 2 - mid.dy);
    final len = to.distance;
    return len < 1e-6 ? Offset.zero : to / len * by;
  }

  @override
  bool shouldRepaint(_EdgeStripePainter old) =>
      old.layout != layout || old.links != links;
}

/// Names every stripe on this phone's edges: which colour joins which
/// neighbour — and asks that neighbour to speak up.
///
/// The stripes alone tell you to line colours up; this tells you *who* with,
/// which is the difference between "match the red" and "match the red with
/// phone 2". It also happens to make a wrong board diagnosable at a glance —
/// if a colour is listed but no stripe is visible, the two halves of that join
/// disagree.
///
/// Tapping a neighbour's chip makes that phone say something in its own
/// player's voice. "Which one is phone 2?" is a question a diagram answers
/// slowly and a noise from the far end of the table answers instantly, and at
/// this moment in the evening it is the only question anybody has.
class _LinkLegend extends StatelessWidget {
  const _LinkLegend({
    required this.links,
    required this.slices,
    required this.onPoke,
  });

  final List<EdgeMarker> links;
  final List<PhoneSlice> slices;
  final ValueChanged<String> onPoke;

  /// Where a phone sits in the board's reading order, 1-based.
  int? _positionOf(String phoneId) {
    for (final (i, s) in slices.indexed) {
      if (s.phoneId == phoneId) return i + 1;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 8,
      children: [
        for (final link in links)
          _LinkChip(
            color: link.isJoin
                ? LinkPalette.of(link.colorIndex)
                : LinkPalette.inward,
            label: link.partnerId == null
                ? 'the middle'
                : 'phone ${_positionOf(link.partnerId!) ?? "?"}',
            // The stripe pointing at the middle of the table has no phone
            // behind it, so there is nothing there to make a noise. That chip
            // stays a label.
            onPoke: link.partnerId == null
                ? null
                : () => onPoke(link.partnerId!),
          ),
      ],
    );
  }
}

/// One stripe's chip: its colour and who is on the other end.
///
/// When that is a phone, tapping it makes them speak — deliberately unmarked;
/// see the plate below.
///
/// Two plates rather than one with a disabled state, because the flow draws a
/// dead control at half opacity and the middle-of-the-table chip is not dead.
/// It is a caption that happens to look like the others, and it should be as
/// legible as they are.
class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.color,
    required this.label,
    required this.onPoke,
  });

  final Color color;
  final String label;
  final VoidCallback? onPoke;

  static const _padding = EdgeInsets.symmetric(horizontal: 16, vertical: 10);

  @override
  Widget build(BuildContext context) {
    final poke = onPoke;
    final words = Text(label, style: LobbyText.button);

    if (poke == null) {
      return Container(
        padding: _padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(LobbyMetrics.pillRadius),
          boxShadow: [
            BoxShadow(
              color: LobbyFlowColors.shadeOf(color),
              offset: const Offset(
                LobbyMetrics.rowOffset,
                LobbyMetrics.rowOffset,
              ),
              blurRadius: 0,
            ),
          ],
        ),
        child: words,
      );
    }

    // The flow's plate at chip size: it sinks into its own shadow when pressed,
    // which is the only feedback this phone gets — the sound it asks for comes
    // out of somebody else's speaker.
    //
    // Nothing marks it as a button. It is meant to be found by somebody idly
    // prodding the screen while the table sorts itself out, and a little
    // speaker icon would turn a discovery into a feature.
    return LobbyCard(
      color: color,
      padding: _padding,
      onTap: poke,
      child: words,
    );
  }
}
