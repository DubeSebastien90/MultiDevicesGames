import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/phone_layout.dart';
import '../contract/sim.dart' show PhoneSlice;
import '../layout/board_links.dart';
import 'board_diagram.dart';
import 'hold_to_confirm.dart';
import 'link_palette.dart';

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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Confirmation state comes from the lobby list, but *positions* come from
    // the compiled board — join order says nothing about where a game decided to
    // put anybody.
    final confirmedIds = <String>{
      for (final p in client.lobbyPhones)
        if ((p['confirmed'] as bool?) ?? false) p['phoneId'] as String,
    };

    final diagram = BoardDiagram(
      slices: client.slices,
      board: layout.board,
      links: client.allLinks,
      meId: client.phoneId,
      confirmed: confirmedIds,
    );

    final legend = client.myLinks.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _LinkLegend(links: client.myLinks, slices: client.slices),
          );

    return Scaffold(
      // Deliberately not turned: you read your own phone the way you hold it,
      // whatever angle its slot in the board happens to be.
      body: Stack(
        children: [
          // The stripes hug the real glass edges, so this fills the screen.
          Positioned.fill(
            child: CustomPaint(
              painter: _EdgeStripePainter(layout: layout, links: client.myLinks),
            ),
          ),

          // The hold target is the whole screen, and now the only thing on it:
          // no button to find, and nothing to hit by accident while your hands
          // are busy holding phones against each other.
          HoldToConfirm(
            confirmed: confirmedIds.contains(client.phoneId),
            onConfirmed: client.confirmPlacement,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [diagram, legend],
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
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF101733),
    );

    /// Where a world point lands on this screen, turn included.
    Offset toScreen(double wx, double wy) {
      final px = layout.worldToPhysicalPx(wx, wy);
      final dpr = layout.devicePixelRatio;
      return Offset(px.x / dpr, px.y / dpr);
    }

    final stripe = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;

    for (final link in links) {
      final a = toScreen(link.x1, link.y1);
      final b = toScreen(link.x2, link.y2);
      // Pull the line a few pixels inside the panel, or half its width falls
      // off the glass.
      final inset = _towardCentre(a, b, size, 5);
      stripe.color =
          link.isJoin ? LinkPalette.of(link.colorIndex) : LinkPalette.inward;
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
/// neighbour.
///
/// The stripes alone tell you to line colours up; this tells you *who* with,
/// which is the difference between "match the red" and "match the red with
/// phone 2". It also happens to make a wrong board diagnosable at a glance —
/// if a colour is listed but no stripe is visible, the two halves of that join
/// disagree.
class _LinkLegend extends StatelessWidget {
  const _LinkLegend({required this.links, required this.slices});

  final List<EdgeMarker> links;
  final List<PhoneSlice> slices;

  /// Where a phone sits in the board's reading order, 1-based.
  int? _positionOf(String phoneId) {
    for (final (i, s) in slices.indexed) {
      if (s.phoneId == phoneId) return i + 1;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final link in links)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 16,
                height: 4,
                decoration: BoxDecoration(
                  color: link.isJoin
                      ? LinkPalette.of(link.colorIndex)
                      : LinkPalette.inward,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              Text(
                link.partnerId == null
                    ? 'the middle'
                    : 'phone ${_positionOf(link.partnerId!) ?? "?"}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
