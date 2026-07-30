import 'package:flutter/material.dart';

import '../app_controller.dart';
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

    final phones = [
      for (final p in client.lobbyPhones)
        StripPhone(
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
                          StripDiagram(phones: phones, height: 70),
                          const SizedBox(height: 12),
                          Text(
                            'Push the phones together until the casings touch, '
                            'with the top edges flush. The guide lines should '
                            'continue straight across the gap.',
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

    final bg = Paint()..color = const Color(0xFF101733);
    canvas.drawRect(Offset.zero & size, bg);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0x40FFFFFF);

    // Horizontal rules across the whole board: a step at the gap means the top
    // edges are not flush.
    for (final f in const [0.2, 0.5, 0.8]) {
      final y = toLocalY(board.top + board.height * f);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }

    // Vertical ticks every 5cm of world space, labelled in world units so both
    // screens show the same numbers in the same physical places.
    final major = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x26FFFFFF);
    for (var wx = 0.0; wx <= board.right; wx += 5) {
      final x = toLocalX(wx);
      if (x < -20 || x > size.width + 20) continue;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), major);
      _label(canvas, '${wx.toInt()}cm', Offset(x + 4, 4));
    }

    // A circle straddling each seam. Correctly placed, the two halves read as
    // one circle with the bezel gap cut out of its middle.
    final seams = coverage?.seamRects() ?? const [];
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = const Color(0x99FF6B4A);
    for (final seam in seams) {
      final center = Offset(
        toLocalX(seam.centerX),
        toLocalY(board.centerY),
      );
      final radius = board.height * 0.32 * pxPerWorld;
      // Skip seams nowhere near this screen.
      if (center.dx < -radius * 2 || center.dx > size.width + radius * 2) {
        continue;
      }
      canvas.drawCircle(center, radius, ring);
      canvas.drawLine(
        Offset(center.dx - radius * 1.4, center.dy),
        Offset(center.dx + radius * 1.4, center.dy),
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
