import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Whether the sticker screens' idle loops run: the title's bob, the pulsing
/// dot, the drifting background.
///
/// These loop forever, which is what they are for and also what makes
/// `pumpAndSettle` wait forever. Widget tests turn this off once, in
/// `test/flutter_test_config.dart`, rather than every test learning to pump a
/// fixed number of frames. A person who asked their phone to reduce motion
/// gets the same stillness through [MediaQuery.disableAnimations].
class StickerMotion {
  const StickerMotion._();

  static bool loops = true;

  static bool of(BuildContext context) =>
      loops && !MediaQuery.of(context).disableAnimations;
}

/// A looping 0→1 clock for the idle animations, stopped when motion is off.
///
/// Shared by [Bob], [Pulse] and [Wiggle]: each is the same controller with a
/// different transform on the end of it.
abstract class _LoopState<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin {
  Duration get period;

  late final AnimationController loop = AnimationController(
    vsync: this,
    duration: period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (StickerMotion.of(context)) {
      if (!loop.isAnimating) loop.repeat();
    } else {
      loop
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }

  /// 0 → 1 → 0 over one period, eased at both ends.
  double get wave => (1 - math.cos(2 * math.pi * loop.value)) / 2;
}

/// A slow bob: up by [distance] and back, eased. The home title.
class Bob extends StatefulWidget {
  const Bob({
    super.key,
    required this.child,
    this.distance = 6,
    this.period = const Duration(milliseconds: 2800),
  });

  final Widget child;
  final double distance;
  final Duration period;

  @override
  State<Bob> createState() => _BobState();
}

class _BobState extends _LoopState<Bob> {
  @override
  Duration get period => widget.period;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: loop,
    builder: (_, child) => Transform.translate(
      offset: Offset(0, -widget.distance * wave),
      child: child,
    ),
    child: widget.child,
  );
}

/// Breathing: scale 1 → [scale], opacity 0.6 → 1. Status dots.
class Pulse extends StatefulWidget {
  const Pulse({
    super.key,
    required this.child,
    this.scale = 1.08,
    this.period = const Duration(milliseconds: 1400),
  });

  final Widget child;
  final double scale;
  final Duration period;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends _LoopState<Pulse> {
  @override
  Duration get period => widget.period;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: loop,
    builder: (_, child) {
      // Still means fully there, not caught at the dim end of a breath.
      final e = StickerMotion.of(context) ? wave : 1.0;
      return Opacity(
        opacity: .6 + .4 * e,
        child: Transform.scale(scale: 1 + (widget.scale - 1) * e, child: child),
      );
    },
    child: widget.child,
  );
}

/// A rocking tilt of ±[deg]. The paywall's crown.
class Wiggle extends StatefulWidget {
  const Wiggle({
    super.key,
    required this.child,
    this.deg = 8,
    this.period = const Duration(milliseconds: 2400),
  });

  final Widget child;
  final double deg;
  final Duration period;

  @override
  State<Wiggle> createState() => _WiggleState();
}

class _WiggleState extends _LoopState<Wiggle> {
  @override
  Duration get period => widget.period;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: loop,
    builder: (_, child) => Transform.rotate(
      angle: -widget.deg * math.pi / 180 * math.cos(2 * math.pi * loop.value),
      child: child,
    ),
    child: widget.child,
  );
}

/// Pops its child in — scale 0.3 → overshoot → 1 — the first time it builds.
class PopIn extends StatelessWidget {
  const PopIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 350),
  });

  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: duration,
    curve: Curves.easeOutBack,
    builder: (_, v, c) => Opacity(
      opacity: v.clamp(0.0, 1.0),
      child: Transform.scale(scale: .3 + .7 * v, child: c),
    ),
    child: child,
  );
}
