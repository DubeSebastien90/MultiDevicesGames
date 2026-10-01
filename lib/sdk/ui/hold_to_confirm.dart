import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../audio/sounds.dart';
import 'sticker/sticker.dart';

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
    this.padding = const EdgeInsets.all(16),
    this.footer,
    this.audio = const SilentLocalAudio(),
  });

  final Widget content;

  final VoidCallback onConfirmed;

  final bool confirmed;

  final String label;
  final String doneLabel;

  final Duration hold;
  final Duration decay;

  final Widget? footer;

  final EdgeInsets padding;

  final LocalAudio audio;

  @override
  State<HoldToConfirm> createState() => _HoldToConfirmState();
}

class _HoldToConfirmState extends State<HoldToConfirm>
    with TickerProviderStateMixin {
  late final AnimationController _progress =
      AnimationController(
          vsync: this,
          duration: widget.hold,
          reverseDuration: widget.decay,
        )
        ..addStatusListener(_onStatus)
        ..addListener(_onProgress);

  int _step = -1;

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

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

    if (!widget.confirmed && _done) {
      _done = false;
      _progress.value = 0;
    }
  }

  void _onProgress() {
    final steps = Sounds.holdSteps;
    final step = (_progress.value * steps.length).floor().clamp(
      0,
      steps.length - 1,
    );
    if (_progress.status != AnimationStatus.forward) {
      if (_progress.value == 0) {
        _step = -1;
      } else if (step < _step) {
        _step = step;
      }
      return;
    }
    if (step <= _step) return;
    _step = step;
    widget.audio.play(steps[step]);
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

    final extra = widget.footer;

    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _down(),
            onPointerUp: (_) => _up(),
            onPointerCancel: (_) => _up(),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: widget.padding,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tall = constraints.maxWidth <= 520;

                final body = tall
                    ? Column(
                        children: [
                          Expanded(child: Center(child: widget.content)),
                          const SizedBox(height: 28),
                          ring,
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: Center(child: widget.content)),
                          const SizedBox(width: 32),
                          ring,
                        ],
                      );

                return Column(
                  children: [
                    Expanded(child: IgnorePointer(child: body)),
                    if (extra != null) ...[const SizedBox(height: 24), extra],
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

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
    return SizedBox.square(
      dimension: _size,
      child: AnimatedBuilder(
        animation: Listenable.merge([progress, spin]),
        builder: (context, _) {
          final value = progress.value;

          final arc = done ? St.go : St.premium;
          return CustomPaint(
            painter: _HoldRingPainter(
              progress: value,
              spin: spin.value,
              arc: arc,
              idle: St.premium.withValues(alpha: 0.3 * (1 - value)),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: done
                      ? St.display(26, height: 1.1)
                      : St.display(15, height: 1.15),
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
    required this.arc,
    required this.idle,
  });

  final double progress;

  final double spin;

  final Color arc;
  final Color idle;

  static const _band = 18.0;

  static const _rim = 3.0;

  static const _shadow = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final outer = size.shortestSide / 2;
    final bandRadius = outer - _rim - _band / 2;
    final box = Rect.fromCircle(center: center, radius: bandRadius);

    canvas.drawCircle(
      center + const Offset(_shadow, _shadow),
      outer,
      Paint()..color = St.ink,
    );
    canvas.drawCircle(center, outer, Paint()..color = St.white);

    final gauge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _band
      ..strokeCap = StrokeCap.round;

    if (idle.a > 0.01) {
      canvas.drawArc(box, spin * 2 * math.pi, 1.1, false, gauge..color = idle);
    }

    if (progress > 0) {
      canvas.drawArc(
        box,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        gauge..color = arc,
      );
    }

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _rim
      ..color = St.ink;
    canvas.drawCircle(center, outer - _rim / 2, rim);
    canvas.drawCircle(center, outer - _rim - _band - _rim / 2, rim);
  }

  @override
  bool shouldRepaint(_HoldRingPainter old) =>
      old.progress != progress ||
      old.spin != spin ||
      old.arc != arc ||
      old.idle != idle;
}
