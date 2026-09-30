import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../audio/sounds.dart';
import 'sticker/sticker.dart';

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
    this.padding = const EdgeInsets.all(16),
    this.footer,
    this.audio = const SilentLocalAudio(),
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

  /// Shown under the ring, and the one part of this screen that may be
  /// touched without holding anything.
  ///
  /// It is a slot rather than part of [content] because of how the two are hit
  /// tested: [content] is made transparent to pointers so the hold underneath
  /// gets them all, while this is left alive, so a button here takes its own
  /// press. Without that, every tap on a chip would fill the ring a little and
  /// a dozen impatient taps would confirm a position nobody confirmed.
  final Widget? footer;

  /// The air around the whole arrangement. The placement screen widens it to
  /// two stripe widths, because its content grows to whatever it is given and
  /// the gutter is the only thing holding it off the edge stripes.
  final EdgeInsets padding;

  /// Where the gauge is heard: a tick per step of the ring, rising as it
  /// fills. This phone's own speaker only — the finger is on this glass.
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

  /// The highest gauge step already sounded, -1 for none.
  ///
  /// Follows the ring down as it drains, silently, so a finger that slips and
  /// comes back picks the climb up where the ring is rather than replaying
  /// the low notes.
  int _step = -1;

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

  void _onProgress() {
    final steps = Sounds.holdSteps;
    final step = (_progress.value * steps.length).floor().clamp(
      0,
      steps.length - 1,
    );
    if (_progress.status != AnimationStatus.forward) {
      // Draining: nothing to hear, only to remember.
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
        // The hold target, and it really is the whole screen: underneath
        // everything, catching every pointer the layer above lets through.
        //
        // Which is all of them but one. The picture and the ring are wrapped in
        // an [IgnorePointer] below, so a finger anywhere on them falls straight
        // through to here; only the footer's buttons are left hittable, and a
        // button that takes the press is a press this never sees. That is the
        // whole trick — no rectangle is carved out of the hold, and no tap on a
        // chip can nudge the ring.
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
                // "Next to" on a portrait phone means underneath.
                final tall = constraints.maxWidth <= 520;

                // [Expanded], not a bare child: the picture is handed whatever
                // the ring and the footer do not want. That is what makes the
                // gutter hold on a short phone — the fixed things keep their
                // size and the one thing that can be drawn smaller is.
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
    return SizedBox.square(
      dimension: _size,
      child: AnimatedBuilder(
        animation: Listenable.merge([progress, spin]),
        builder: (context, _) {
          final value = progress.value;
          // Green once the promise is made, purple while it is being made —
          // the purple of the standings card, so the one thing on this screen
          // that moves under your finger wears the flow's accent.
          final arc = done ? St.go : St.premium;
          return CustomPaint(
            painter: _HoldRingPainter(
              progress: value,
              spin: spin.value,
              arc: arc,
              // The idle sweep in the same purple, washed out and fading as the
              // hold takes over, so a comet going round never reads as the
              // hold itself.
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

/// A round white sticker — ink rim, hard shadow — with the gauge running in a
/// band between two ink rings.
class _HoldRingPainter extends CustomPainter {
  _HoldRingPainter({
    required this.progress,
    required this.spin,
    required this.arc,
    required this.idle,
  });

  /// 0 to 1: how much of the hold has been served.
  final double progress;

  /// 0 to 1, looping: where the idle sweep has got to.
  final double spin;

  final Color arc;
  final Color idle;

  /// Matches the edge stripes' width, so the ring and the bands on the glass
  /// are strokes of one weight rather than two.
  static const _band = 18.0;

  /// The sticker outline, as thick as every other sticker's.
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

    // The idle sweep — a comet chasing the ring, fading as the hold fills.
    if (idle.a > 0.01) {
      canvas.drawArc(box, spin * 2 * math.pi, 1.1, false, gauge..color = idle);
    }

    // The hold itself, from the top, clockwise.
    if (progress > 0) {
      canvas.drawArc(
        box,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        gauge..color = arc,
      );
    }

    // The rims last, so the gauge sits in a channel rather than over its
    // edges.
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
