import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/coverage_map.dart';
import '../model/phone_layout.dart';
import 'board_diagram.dart';

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
      body: Stack(
        children: [
          // The alignment guide fills the screen, edge to edge, because the
          // millimetres at the edges are the ones that matter.
          Positioned.fill(
            child: CustomPaint(
              painter: _AlignmentGuidePainter(
                layout: layout,
                coverage: client.coverage,
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
                            meId: client.phoneId,
                            confirmed: confirmedIds,
                          ),
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
  _AlignmentGuidePainter({required this.layout, required this.coverage});

  final PhoneLayout layout;
  final CoverageMap? coverage;

  @override
  void paint(Canvas canvas, Size size) {
    final board = layout.board;
    final pxPerWorld = layout.logicalPxPerWorldUnit;

    double toLocalX(double wx) => (wx - layout.worldOffsetX) * pxPerWorld;
    double toLocalY(double wy) => (wy - layout.worldOffsetY) * pxPerWorld;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF101733),
    );

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
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      }
      for (var wx = 0.0; wx <= board.right; wx += 5) {
        final x = toLocalX(wx);
        if (x < -20 || x > size.width + 20) continue;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), major);
        _label(canvas, '${wx.toInt()}cm', Offset(x + 4, 4));
      }
    }
    if (hasHorizontal) {
      for (final f in const [0.2, 0.5, 0.8]) {
        final x = toLocalX(board.left + board.width * f);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      }
      for (var wy = 0.0; wy <= board.bottom; wy += 5) {
        final y = toLocalY(wy);
        if (y < -20 || y > size.height + 20) continue;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), major);
        _label(canvas, '${wy.toInt()}cm', Offset(4, y + 4));
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
      final radius =
          (vertical ? seam.height : seam.width) * 0.32 * pxPerWorld;
      if (radius <= 0) continue;

      // Skip seams nowhere near this screen.
      if (center.dx < -radius * 2 ||
          center.dx > size.width + radius * 2 ||
          center.dy < -radius * 2 ||
          center.dy > size.height + radius * 2) {
        continue;
      }

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
      old.layout != layout || old.coverage != coverage;
}
