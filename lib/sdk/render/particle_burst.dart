import 'dart:math' as math;

import 'package:flutter/widgets.dart';

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
  final travel = speed * seconds * (1 - math.pow(1 - t, 2.4).toDouble()) * 0.45;

  final fade = math.pow(1 - t, 1.6).toDouble();
  final size = particleRadius * (1 - 0.55 * t);

  for (var i = 0; i < count; i++) {
    final wobble = _scatter(i);
    final angle = i * 2 * math.pi / count + wobble * 0.4;
    final reach = travel * (0.55 + 0.45 * _scatter(i + 97).abs());

    fill.color = color.withValues(alpha: color.a * fade);
    canvas.drawCircle(
      Offset(at.dx + math.cos(angle) * reach, at.dy + math.sin(angle) * reach),
      size * (0.7 + 0.5 * _scatter(i + 31).abs()),
      fill,
    );
  }
}

double _scatter(int i) {
  final v = math.sin(i * 12.9898) * 43758.5453;
  return (v - v.floorToDouble()) * 2 - 1;
}
