import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Press anywhere and keep pressing: a ring fills, and at the end of it the
/// answer is yes.
///
/// A hold rather than a button because both hands are busy holding phones
/// against each other, and a stray tap while sliding a phone into place should
/// not claim "I am ready". Letting go does not throw the progress away either —
/// it drains, slower than it filled, so a finger that slips is a stumble and not
/// a restart.
///
/// [content] sits beside the ring — or above it, when the screen is too narrow
/// for beside to mean anything.
class HoldToConfirm extends StatefulWidget {
  const HoldToConfirm({
    super.key,
    required this.content,
    required this.onConfirmed,
    this.confirmed = false,
    this.label = 'Hold to confirm position',
    this.doneLabel = 'Ready',
    this.hold = const Duration(seconds: 1),
    this.decay = const Duration(milliseconds: 2200),
  });

  /// Shown next to the ring. The reason someone is holding at all.
  final Widget content;

  /// Fired once, the moment the ring fills.
  final VoidCallback onConfirmed;

  /// Already confirmed somewhere else — a reconnect, or a rebuild. The ring
  /// starts full rather than inviting a hold that would do nothing.
  final bool confirmed;

  final String label;
  final String doneLabel;

  final Duration hold;
  final Duration decay;

  @override
  State<HoldToConfirm> createState() => _HoldToConfirmState();
}

class _HoldToConfirmState extends State<HoldToConfirm>
    with TickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: widget.hold,
    reverseDuration: widget.decay,
  )..addStatusListener(_onStatus);

  /// The idle animation: something alive on screen while people shuffle phones
  /// around. Fades out as the hold takes over, so the two never compete.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  /// Set the instant the hold completes, rather than waiting for a round trip —
  /// the finger earned "Ready" already.
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.confirmed) {
      _done = true;
      _progress.value = 1;
    }
  }

  @override
  void didUpdateWidget(HoldToConfirm old) {
    super.didUpdateWidget(old);
    if (widget.confirmed && !_done) {
      _done = true;
      _progress.value = 1;
      return;
    }

    // Being told it is no longer confirmed has to undo it. This latched once
    // and stayed latched, and because Flutter reuses this State for the next
    // round, a second round opened already saying "Ready" — with the hold
    // disabled, since it thought the job was done. Nobody could confirm, and
    // the host waited for a phone that had no way to answer.
    if (!widget.confirmed && _done) {
      _done = false;
      _progress.value = 0;
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || _done) return;
    setState(() => _done = true);
    widget.onConfirmed();
  }

  @override
  void dispose() {
    _progress.dispose();
    _spin.dispose();
    super.dispose();
  }

  void _down() {
    if (!_done) _progress.forward();
  }

  void _up() {
    if (!_done) _progress.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final ring = _HoldRing(
      progress: _progress,
      spin: _spin,
      done: _done,
      label: _done ? widget.doneLabel : widget.label,
    );

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _down(),
      onPointerUp: (_) => _up(),
      onPointerCancel: (_) => _up(),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // "Next to" on a portrait phone means underneath.
                if (constraints.maxWidth <= 520) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      widget.content,
                      const SizedBox(height: 28),
                      ring,
                    ],
                  );
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: widget.content),
                    const SizedBox(width: 32),
                    ring,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The loading circle: idle sweep, hold progress, and the word in the middle.
class _HoldRing extends StatelessWidget {
  const _HoldRing({
    required this.progress,
    required this.spin,
    required this.done,
    required this.label,
  });

  final Animation<double> progress;
  final Animation<double> spin;
  final bool done;
  final String label;

  static const _size = 148.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox.square(
      dimension: _size,
      child: AnimatedBuilder(
        animation: Listenable.merge([progress, spin]),
        builder: (context, _) {
          final value = progress.value;
          return CustomPaint(
            painter: _HoldRingPainter(
              progress: value,
              spin: spin.value,
              track: scheme.onSurface.withValues(alpha: 0.12),
              arc: done ? scheme.tertiary : scheme.primary,
              idle: scheme.primary.withValues(alpha: 0.55 * (1 - value)),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: (done
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.labelMedium)
                      ?.copyWith(
                    color: done ? scheme.tertiary : scheme.onSurfaceVariant,
                    height: 1.15,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HoldRingPainter extends CustomPainter {
  _HoldRingPainter({
    required this.progress,
    required this.spin,
    required this.track,
    required this.arc,
    required this.idle,
  });

  /// 0 to 1: how much of the hold has been served.
  final double progress;

  /// 0 to 1, looping: where the idle sweep has got to.
  final double spin;

  final Color track;
  final Color arc;
  final Color idle;

  static const _stroke = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - _stroke) / 2;
    final box = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke
        ..color = track,
    );

    // The idle sweep — a comet chasing the ring, fading as the hold fills.
    if (idle.a > 0.01) {
      canvas.drawArc(
        box,
        spin * 2 * math.pi,
        1.1,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..color = idle,
      );
    }

    // The hold itself, from the top, clockwise.
    if (progress > 0) {
      canvas.drawArc(
        box,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _stroke
          ..strokeCap = StrokeCap.round
          ..color = arc,
      );
    }
  }

  @override
  bool shouldRepaint(_HoldRingPainter old) =>
      old.progress != progress ||
      old.spin != spin ||
      old.arc != arc ||
      old.idle != idle ||
      old.track != track;
}
