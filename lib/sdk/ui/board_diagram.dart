import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../contract/sim.dart' show PhoneSlice;
import '../layout/board_links.dart';
import '../model/world_rect.dart';
import 'link_palette.dart';

/// A to-scale picture of the board the game actually compiled.
///
/// Drawn straight from the compiled screens, so it shows the real order, the
/// real gaps, the real cross-alignment — **and the real angles**. A ring of
/// phones facing outward draws as a ring of turned phones; a row draws as a
/// row. Nothing here knows what shape a board is supposed to be.
///
/// Two earlier versions of this were wrong in instructive ways. The first laid
/// chips out in a `Row` in join order, which broke the moment a game sorted its
/// phones. The second used each screen's bounding box, which is fine until a
/// phone is turned — and then a 72° phone in a circle draws as a fat upright
/// rectangle that looks nothing like the thing on the table.
class BoardDiagram extends StatelessWidget {
  const BoardDiagram({
    super.key,
    required this.slices,
    required this.board,
    this.links = const [],
    this.meId,
    this.confirmed = const {},
    this.maxExtent = 170,
  });

  /// Every screen's place on the board, in board order.
  final List<PhoneSlice> slices;

  /// The playfield, for proportions.
  final WorldRect board;

  /// Every screen's edge stripes — *all* of them, not just this phone's. Seeing
  /// both ends of a red join in the picture is what makes the red line on your
  /// own glass mean something.
  final List<EdgeMarker> links;

  /// Highlighted as "you".
  final String? meId;

  /// Phone ids that have confirmed their position.
  final Set<String> confirmed;

  /// The most room the drawing may take along its longer axis.
  final double maxExtent;

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      return SizedBox(
        height: 60,
        child: Center(
          child: Text(
            'No phones yet',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }

    // Frame the union of the playfield and every screen, so a phone sticking
    // out past the board — or a whole ring around it — is never clipped.
    var left = board.left;
    var top = board.top;
    var right = board.right;
    var bottom = board.bottom;
    for (final s in slices) {
      final b = s.viewport; // bounding box: right for framing, not for drawing
      left = math.min(left, b.left);
      top = math.min(top, b.top);
      right = math.max(right, b.right);
      bottom = math.max(bottom, b.bottom);
    }
    final frameWidth = right - left;
    final frameHeight = bottom - top;
    if (frameWidth <= 0 || frameHeight <= 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: frameWidth >= frameHeight ? maxExtent * 2.2 : maxExtent,
          maxHeight: maxExtent,
        ),
        child: AspectRatio(
          aspectRatio: frameWidth / frameHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scale = constraints.maxWidth / frameWidth;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // The playfield, so a screen reaching past it is visible as
                  // exactly that.
                  Positioned(
                    left: (board.left - left) * scale,
                    top: (board.top - top) * scale,
                    width: board.width * scale,
                    height: board.height * scale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  for (final (i, slice) in slices.indexed)
                    _positionedScreen(slice, i, left, top, scale, scheme),
                  // Drawn over the screens so a join reads as one band even
                  // where two phones nearly touch.
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _LinkPainter(
                        links: links,
                        left: left,
                        top: top,
                        scale: scale,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// One screen, drawn at its true size *and its true angle*.
  ///
  /// Positioned by its centre rather than a corner, because a turned rectangle
  /// has no corner worth measuring from — the same reason the layout itself is
  /// centre-based.
  Widget _positionedScreen(
    PhoneSlice slice,
    int index,
    double left,
    double top,
    double scale,
    ColorScheme scheme,
  ) {
    final screen = slice.screen;
    final w = screen.width * scale;
    final h = screen.height * scale;

    return Positioned(
      left: (screen.centerX - left) * scale - w / 2,
      top: (screen.centerY - top) * scale - h / 2,
      width: w,
      height: h,
      child: Transform.rotate(
        angle: screen.turnRadians,
        child: _Screen(
          index: index,
          label: slice.label,
          isMe: slice.phoneId == meId,
          confirmed: confirmed.contains(slice.phoneId),
          turnRadians: screen.turnRadians,
          scheme: scheme,
        ),
      ),
    );
  }
}

class _Screen extends StatelessWidget {
  const _Screen({
    required this.index,
    required this.label,
    required this.isMe,
    required this.confirmed,
    required this.turnRadians,
    required this.scheme,
  });

  final int index;
  final String label;
  final bool isMe;
  final bool confirmed;
  final double turnRadians;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final edge = isMe ? scheme.primary : scheme.outlineVariant;

    return Container(
      decoration: BoxDecoration(
        color: isMe
            ? scheme.primary.withValues(alpha: 0.22)
            : scheme.surfaceContainerHigh,
        border: Border.all(color: edge, width: isMe ? 2 : 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // A bar along the phone's own top edge. With everything turned, this
          // is what tells you which way round to put it down — a rectangle
          // alone cannot say which end is up.
          Align(
            alignment: Alignment.topCenter,
            child: FractionallySizedBox(
              widthFactor: 0.45,
              child: Container(
                height: 2.5,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: edge,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          // Turned back, so the writing stays readable however the phone lies.
          Transform.rotate(
            angle: -turnRadians,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isMe ? 'YOU' : '${index + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isMe ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (label.isNotEmpty)
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 8,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  if (confirmed)
                    Icon(Icons.check_circle, size: 10, color: scheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// The edge stripes, in the schema's own little coordinate space.
class _LinkPainter extends CustomPainter {
  _LinkPainter({
    required this.links,
    required this.left,
    required this.top,
    required this.scale,
  });

  final List<EdgeMarker> links;
  final double left;
  final double top;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (final link in links) {
      stroke.color = link.isJoin
          ? LinkPalette.of(link.colorIndex)
          : LinkPalette.inward;
      canvas.drawLine(
        Offset((link.x1 - left) * scale, (link.y1 - top) * scale),
        Offset((link.x2 - left) * scale, (link.y2 - top) * scale),
        stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) =>
      old.links != links || old.scale != scale;
}
