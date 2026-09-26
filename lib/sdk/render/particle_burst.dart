import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// One burst: round bits of [color] thrown out of [at], slowing and fading.
///
/// A pure function of [t], 0 to 1 — no particle list, no per-frame state.
/// Every bit's direction and speed comes from its own index, so the burst is
/// the same burst on every phone and costs nothing to keep between frames.
///
/// [particleRadius] is the size of a bit at the start; they shrink as they go.
void drawParticleBurst(
  Canvas canvas,
  Paint fill,
  Offset at,
  Color color,
  double t, {
  required int count,
  required double speed,
  required double seconds,
  required double particleRadius,
}) {
  // Slowing as they go, rather than flying at a constant rate: the give in
  // the first tenth of a second is most of what makes it read as a burst.
  final travel =
      speed * seconds * (1 - math.pow(1 - t, 2.4).toDouble()) * 0.45;

  final fade = math.pow(1 - t, 1.6).toDouble();
  final size = particleRadius * (1 - 0.55 * t);

  for (var i = 0; i < count; i++) {
    // Spread evenly, then nudged off the ring by a number that depends only
    // on which bit this is — a tidy circle of dots looks like a diagram.
    final wobble = _scatter(i);
    final angle = i * 2 * math.pi / count + wobble * 0.4;
    final reach = travel * (0.55 + 0.45 * _scatter(i + 97).abs());

    fill.color = color.withValues(alpha: color.a * fade);
    canvas.drawCircle(
      Offset(
        at.dx + math.cos(angle) * reach,
        at.dy + math.sin(angle) * reach,
      ),
      size * (0.7 + 0.5 * _scatter(i + 31).abs()),
      fill,
    );
  }
}

/// A repeatable number in (-1, 1) for [i]. Not random — the same bit must
/// fly the same way on every phone, and on this one every frame.
double _scatter(int i) {
  final v = math.sin(i * 12.9898) * 43758.5453;
  return (v - v.floorToDouble()) * 2 - 1;
}
