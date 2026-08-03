import 'package:flutter/material.dart';

import '../contract/sim.dart' show PhoneSlice;
import '../model/world_rect.dart';

/// A to-scale picture of the board the game actually compiled.
///
/// Drawn straight from the world rectangles the host sent, so it shows the real
/// order, the real gaps and the real cross-alignment — for any layout, not just
/// a row or a column. A grid draws as a grid; a phone the game deliberately set
/// apart shows as set apart.
///
/// The version this replaced laid chips out in a `Row` in *join* order, which
/// was wrong the moment a game sorted its phones — and both shipped games do.
class BoardDiagram extends StatelessWidget {
  const BoardDiagram({
    super.key,
    required this.slices,
    required this.board,
    this.meId,
    this.confirmed = const {},
    this.maxExtent = 150,
  });

  /// Every screen's place on the board, in board order.
  final List<PhoneSlice> slices;

  /// The playfield, for proportions.
  final WorldRect board;

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

    // A screen can stick out past the playfield when phones differ in size, so
    // frame the union rather than the board alone and let nothing be clipped.
    var left = board.left;
    var top = board.top;
    var right = board.right;
    var bottom = board.bottom;
    for (final s in slices) {
      final r = s.viewport;
      if (r.left < left) left = r.left;
      if (r.top < top) top = r.top;
      if (r.right > right) right = r.right;
      if (r.bottom > bottom) bottom = r.bottom;
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
                children: [
                  // The playfield, so a screen sticking out past it is visible
                  // as exactly that.
                  Positioned(
                    left: (board.left - left) * scale,
                    top: (board.top - top) * scale,
                    width: board.width * scale,
                    height: board.height * scale,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  for (final (i, slice) in slices.indexed)
                    Positioned(
                      left: (slice.viewport.left - left) * scale,
                      top: (slice.viewport.top - top) * scale,
                      width: slice.viewport.width * scale,
                      height: slice.viewport.height * scale,
                      child: _Screen(
                        index: i,
                        label: slice.label,
                        isMe: slice.phoneId == meId,
                        confirmed: confirmed.contains(slice.phoneId),
                        scheme: scheme,
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
}

class _Screen extends StatelessWidget {
  const _Screen({
    required this.index,
    required this.label,
    required this.isMe,
    required this.confirmed,
    required this.scheme,
  });

  final int index;
  final String label;
  final bool isMe;
  final bool confirmed;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isMe
            ? scheme.primary.withValues(alpha: 0.22)
            : scheme.surfaceContainerHigh,
        border: Border.all(
          color: isMe ? scheme.primary : scheme.outlineVariant,
          width: isMe ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.all(2),
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
      ),
    );
  }
}
