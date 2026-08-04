import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/coverage_map.dart';
import '../model/phone_layout.dart';
import '../contract/sim.dart' show PhoneSlice;
import '../layout/board_links.dart';
import 'board_diagram.dart';
import 'link_palette.dart';

/// "Place yourself here", then Confirm.
///
/// This screen also carries the game's identity — title, goal, and the one-line
/// instruction its `planBoard` produced. There is no separate arrangement step
/// any more, so this is the first and only time people are told what they are
/// about to play and where to stand for it.
///
/// Nothing measures whether the phones are actually where the host thinks they
/// are — Confirm is a human promise, not a sensor reading. What this screen can
/// do is make a wrong promise *visible*: the guide lines are drawn in world
/// coordinates, so on correctly placed phones they run unbroken across the gap.
class PlacementView extends StatelessWidget {
  const PlacementView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final client = controller.client!;
    final layout = client.layout;
    final theme = Theme.of(context);

    if (layout == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Confirmation state still comes from the lobby list, but *positions* come
    // from the compiled board — join order says nothing about where a game
    // decided to put anybody.
    final confirmedIds = <String>{
      for (final p in client.lobbyPhones)
        if ((p['confirmed'] as bool?) ?? false) p['phoneId'] as String,
    };
    final confirmed = confirmedIds.contains(client.phoneId);
    final manifest = client.manifest;

    return Scaffold(
      // Deliberately not turned: you read your own phone the way you hold it,
      // whatever angle its slot in the board happens to be. The camera handles
      // the board's rotation; doing it here too would turn everything twice.
      body: Stack(
        children: [
          // The alignment guide fills the screen, edge to edge, because the
          // millimetres at the edges are the ones that matter.
          Positioned.fill(
            child: CustomPaint(
              painter: _AlignmentGuidePainter(
                layout: layout,
                coverage: client.coverage,
                links: client.myLinks,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Card(
                    color: theme.colorScheme.surface.withValues(alpha: 0.92),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (manifest != null) ...[
                            Text(
                              manifest.title,
                              style: theme.textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              manifest.goal,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                          ],
                          Text(
                            'Phone ${layout.index + 1} of ${layout.total}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            layout.placement,
                            style: theme.textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          BoardDiagram(
                            slices: client.slices,
                            board: layout.board,
                            links: client.allLinks,
                            meId: client.phoneId,
                            confirmed: confirmedIds,
                          ),
                          if (client.myLinks.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _LinkLegend(
                              links: client.myLinks,
                              slices: client.slices,
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            client.instruction ??
                                'Push the phones together until the casings '
                                    'touch. The guide lines should continue '
                                    'straight across the gap.',
                            style: theme.textTheme.bodySmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 14),
                          if (confirmed)
                            Column(
                              children: [
                                const Icon(Icons.check_circle, size: 28),
                                const SizedBox(height: 6),
                                Text(
                                  'Waiting for the others…',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ],
                            )
                          else
                            FilledButton.icon(
                              onPressed: client.confirmPlacement,
                              icon: const Icon(Icons.check),
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Text('In place — confirm'),
                              ),
                            ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: controller.leave,
                            child: const Text('Leave'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Guide lines drawn in *world* coordinates, so on correctly placed phones they
/// run unbroken across the physical gap.
///
/// The rules that expose a misalignment must run *across* the seams, and the
/// seams can now run either way — a row has vertical ones, a column horizontal,
/// a grid both. So the guide is derived from the seams themselves rather than
/// from any declared axis: draw the wrong set and a badly placed board looks
/// perfect.
class _AlignmentGuidePainter extends CustomPainter {
  _AlignmentGuidePainter({
    required this.layout,
    required this.coverage,
    required this.links,
  });

  final PhoneLayout layout;
  final CoverageMap? coverage;

  /// This phone's edge stripes. The most actionable thing on the screen: line
  /// the colours up with your neighbours' and the board is right.
  final List<EdgeMarker> links;

  @override
  void paint(Canvas canvas, Size size) {
    final board = layout.board;
    final pxPerWorld = layout.logicalPxPerWorldUnit;

    // World-aligned local pixels, measured from the middle of this screen.
    // Used *inside* the rotated block below, which supplies the turn.
    double toLocalX(double wx) =>
        size.width / 2 + (wx - layout.worldCenterX) * pxPerWorld;
    double toLocalY(double wy) =>
        size.height / 2 + (wy - layout.worldCenterY) * pxPerWorld;

    /// Where a world point lands on this screen, turn included — for anything
    /// that must be drawn upright rather than with the world.
    Offset toScreen(double wx, double wy) {
      final px = layout.worldToPhysicalPx(wx, wy);
      final dpr = layout.devicePixelRatio;
      return Offset(px.x / dpr, px.y / dpr);
    }

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF101733),
    );

    // The guide is a picture of the *world*, so it turns with the phone's slot
    // in the board — that is the whole point of it, since these lines are what
    // must run unbroken from one screen to the next. Everything drawn between
    // here and the matching restore is in world-aligned coordinates.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-layout.turnRadians);
    canvas.translate(-size.width / 2, -size.height / 2);

    // Lines have to overhang, because a turned screen sees beyond its own
    // width along a world axis.
    final span = size.longestSide * 2;

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x40FFFFFF);
    final major = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x26FFFFFF);

    final seams = coverage?.seamRects() ?? const [];

    // A seam taller than it is wide runs vertically, so horizontal rules cross
    // it. With no seams at all (one phone), draw both sets.
    final hasVertical = seams.isEmpty || seams.any((s) => s.height > s.width);
    final hasHorizontal = seams.isEmpty || seams.any((s) => s.width > s.height);

    if (hasVertical) {
      for (final f in const [0.2, 0.5, 0.8]) {
        final y = toLocalY(board.top + board.height * f);
        canvas.drawLine(Offset(-span, y), Offset(span, y), line);
      }
      for (var wx = 0.0; wx <= board.right; wx += 5) {
        final x = toLocalX(wx);
        canvas.drawLine(Offset(x, -span), Offset(x, span), major);
      }
    }
    if (hasHorizontal) {
      for (final f in const [0.2, 0.5, 0.8]) {
        final x = toLocalX(board.left + board.width * f);
        canvas.drawLine(Offset(x, -span), Offset(x, span), line);
      }
      for (var wy = 0.0; wy <= board.bottom; wy += 5) {
        final y = toLocalY(wy);
        canvas.drawLine(Offset(-span, y), Offset(span, y), major);
      }
    }

    // A circle straddling each seam. Correctly placed, the two halves read as
    // one circle with the gap cut out of its middle.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0x99FF6B4A);
    for (final seam in seams) {
      final vertical = seam.height > seam.width;
      final center = Offset(toLocalX(seam.centerX), toLocalY(seam.centerY));
      final radius = (vertical ? seam.height : seam.width) * 0.32 * pxPerWorld;
      if (radius <= 0) continue;

      canvas.drawCircle(center, radius, ring);
      // A bar through the middle, perpendicular to the seam, so the two halves
      // have something to line up against.
      canvas.drawLine(
        vertical
            ? Offset(center.dx - radius * 1.4, center.dy)
            : Offset(center.dx, center.dy - radius * 1.4),
        vertical
            ? Offset(center.dx + radius * 1.4, center.dy)
            : Offset(center.dx, center.dy + radius * 1.4),
        ring,
      );
    }

    canvas.restore();

    // The edge stripes, hugging the real screen edge. Drawn thick and inset
    // just enough to be visible, since the point is to hold two phones
    // together and see one continuous band of colour.
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
      stripe.color = LinkPalette.of(link.colorIndex);
      canvas.drawLine(a + inset, b + inset, stripe);
    }

    // Distance markers last and unrotated: they are labels for a person, not
    // part of the world, and a sideways '15cm' helps nobody.
    for (var w = 0.0; w <= math.max(board.right, board.bottom); w += 5) {
      for (final at in [
        toScreen(w, layout.worldCenterY),
        toScreen(layout.worldCenterX, w),
      ]) {
        if (at.dx < 0 || at.dx > size.width) continue;
        if (at.dy < 0 || at.dy > size.height) continue;
        _label(canvas, '${w.toInt()}cm', at + const Offset(4, 4));
      }
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

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_AlignmentGuidePainter old) =>
      old.layout != layout || old.coverage != coverage || old.links != links;
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
                  color: LinkPalette.of(link.colorIndex),
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
