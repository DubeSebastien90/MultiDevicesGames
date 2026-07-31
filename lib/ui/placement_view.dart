import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../model/arrangement.dart';
import '../model/coverage_map.dart';
import '../model/phone_layout.dart';
import 'strip_diagram.dart';

/// "Place yourself here", then Confirm.
///
/// Nothing measures whether the phones are actually where the host thinks they
/// are — Confirm is a human promise, not a sensor reading. What this screen can
/// do is make a wrong promise *visible*: the guide lines are drawn in world
/// coordinates, so on correctly placed phones they run unbroken across the gap.
/// If a line steps at the seam, either the placement or a measurement is off.
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

    final arrangement = client.arrangement;

    final phones = [
      for (final p in client.lobbyPhones)
        DiagramPhone(
          label: (p['label'] as String?) ?? '?',
          widthMm: (p['widthMm'] as num?)?.toDouble() ?? 70,
          heightMm: (p['heightMm'] as num?)?.toDouble() ?? 150,
          isMe: p['phoneId'] == client.phoneId,
          confirmed: (p['confirmed'] as bool?) ?? false,
          connected: (p['connected'] as bool?) ?? true,
        ),
    ];

    final confirmed = phones.any((p) => p.isMe && p.confirmed);

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
                arrangement: arrangement,
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
                          ArrangementDiagram(
                            phones: phones,
                            arrangement: arrangement,
                            extent: arrangement.isHorizontal ? 70 : 120,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            arrangement.alignmentHint,
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
/// Everything here is mirrored about the packing axis. A strip has vertical
/// seams, so the rules that expose a misalignment run horizontally; a stack has
/// horizontal seams, so they run vertically. Drawing the wrong set would make a
/// badly placed board look perfect.
class _AlignmentGuidePainter extends CustomPainter {
  _AlignmentGuidePainter({
    required this.layout,
    required this.coverage,
    required this.arrangement,
  });

  final PhoneLayout layout;
  final CoverageMap? coverage;
  final Arrangement arrangement;

  @override
  void paint(Canvas canvas, Size size) {
    final board = layout.board;
    final pxPerWorld = layout.logicalPxPerWorldUnit;
    final horizontal = arrangement.isHorizontal;

    double toLocalX(double wx) => (wx - layout.worldOffsetX) * pxPerWorld;
    double toLocalY(double wy) => (wy - layout.worldOffsetY) * pxPerWorld;

    final bg = Paint()..color = const Color(0xFF101733);
    canvas.drawRect(Offset.zero & size, bg);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x40FFFFFF);

    // Rules running *across* the seams: a step in one of these is exactly what
    // a misaligned edge looks like.
    for (final f in const [0.2, 0.5, 0.8]) {
      if (horizontal) {
        final y = toLocalY(board.top + board.height * f);
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      } else {
        final x = toLocalX(board.left + board.width * f);
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      }
    }

    // Ticks every 5cm along the packing axis, labelled in world units so both
    // screens show the same numbers in the same physical places.
    final major = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x26FFFFFF);
    final limit = horizontal ? board.right : board.bottom;
    for (var w = 0.0; w <= limit; w += 5) {
      if (horizontal) {
        final x = toLocalX(w);
        if (x < -20 || x > size.width + 20) continue;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), major);
        _label(canvas, '${w.toInt()}cm', Offset(x + 4, 4));
      } else {
        final y = toLocalY(w);
        if (y < -20 || y > size.height + 20) continue;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), major);
        _label(canvas, '${w.toInt()}cm', Offset(4, y + 4));
      }
    }

    // A circle straddling each seam. Correctly placed, the two halves read as
    // one circle with the bezel gap cut out of its middle.
    final seams = coverage?.seamRects() ?? const [];
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0x99FF6B4A);
    for (final seam in seams) {
      final center = horizontal
          ? Offset(toLocalX(seam.centerX), toLocalY(board.centerY))
          : Offset(toLocalX(board.centerX), toLocalY(seam.centerY));
      final radius =
          (horizontal ? board.height : board.width) * 0.32 * pxPerWorld;

      // Skip seams nowhere near this screen.
      if (horizontal) {
        if (center.dx < -radius * 2 || center.dx > size.width + radius * 2) {
          continue;
        }
      } else {
        if (center.dy < -radius * 2 || center.dy > size.height + radius * 2) {
          continue;
        }
      }

      canvas.drawCircle(center, radius, ring);
      // A bar through the middle, perpendicular to the seam, so the two halves
      // have something to line up against.
      canvas.drawLine(
        horizontal
            ? Offset(center.dx - radius * 1.4, center.dy)
            : Offset(center.dx, center.dy - radius * 1.4),
        horizontal
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
      old.layout != layout ||
      old.coverage != coverage ||
      old.arrangement != arrangement;
}
