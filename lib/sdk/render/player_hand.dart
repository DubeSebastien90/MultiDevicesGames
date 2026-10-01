library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../model/player_color.dart';
import 'tinted_rive.dart';

class PlayerHand {
  PlayerHand._(this.color);

  factory PlayerHand.of(PlayerColor color) =>
      _cache[color.id] ??= PlayerHand._(color);

  static final _cache = <String, PlayerHand>{};

  static void preload(Iterable<PlayerColor> colors) {
    for (final color in colors) {
      PlayerHand.of(color).beginLoading();
    }
  }

  final PlayerColor color;

  static final _art = TintedRive(
    'assets/sdk/players/hand.riv',
    property: 'HandColor',
  );

  bool get isLoaded => _art.artboard(color.value) != null;

  static const _cut = Offset(105.5, 490);

  static const _palm = Offset(285, 205);

  static const _cutWidth = 112.0;

  static final _reachAngle = math.atan2(_palm.dy - _cut.dy, _palm.dx - _cut.dx);
  static final _reachLength = (_palm - _cut).distance;

  void beginLoading() => _art.artboard(color.value);

  void draw(
    Canvas canvas,
    Offset palm, {
    required double angle,
    required double length,
    bool left = false,
    double opacity = 1,
  }) {
    if (length <= 0) return;
    final scale = length / _reachLength;

    canvas
      ..save()
      ..translate(palm.dx, palm.dy)
      ..rotate(angle);

    if (left) canvas.scale(1, -1);

    final artboard = _art.artboard(color.value);
    if (artboard == null) {
      _drawFallback(canvas, length, _cutWidth * scale, opacity);
    } else {
      canvas
        ..rotate(-_reachAngle)
        ..scale(scale)
        ..translate(-_palm.dx, -_palm.dy);
      TintedRive.paint(canvas, artboard, opacity: opacity);
    }
    canvas.restore();
  }

  final _fill = Paint()..isAntiAlias = true;

  void _drawFallback(
    Canvas canvas,
    double length,
    double width,
    double opacity,
  ) {
    _fill.color = color.value.withValues(alpha: opacity);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-length, -width / 2, width / 2, width / 2),
        Radius.circular(width * 0.35),
      ),
      _fill,
    );
  }
}
