import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/client/snapshot_buffer.dart';
import 'package:multiscreen_slingshot/sdk/net/protocol.dart';

Snapshot snap({
  required double t,
  required double x,
  double y = 0,
  double angle = 0,
  double vx = 0,
  double vy = 0,
}) => Snapshot(
  tick: (t / 16.6667).round(),
  hostTimeMs: t,
  entities: {
    'bird': EntityState(id: 'bird', x: x, y: y, angle: angle, vx: vx, vy: vy),
  },
);

void main() {
  test('interpolates between the two snapshots bracketing the render clock', () {
    final buffer = SnapshotBuffer()..interpDelayMs = 50;
    buffer
      ..add(snap(t: 0, x: 0))
      ..add(snap(t: 100, x: 10))
      // The first advance seeds the clock at newest - delay = 50ms.
      ..advance(0);

    expect(buffer.renderTimeMs, closeTo(50, 1e-9));
    expect(buffer.sampleAll()['bird']!.x, closeTo(5, 1e-9));
    expect(buffer.extrapolating, isFalse);
  });

  test('extrapolates along velocity when nothing newer has arrived, but caps it',
      () {
    final buffer = SnapshotBuffer()..interpDelayMs = 0;
    buffer
      ..add(snap(t: 0, x: 0, vx: 10))
      ..advance(0)
      // A whole second with no snapshots: the stream has stalled.
      ..advance(1000);

    final bird = buffer.sampleAll()['bird']!;
    // Capped at 120ms of invented motion: 10 units/s * 0.12s.
    expect(bird.x, closeTo(1.2, 1e-9));
    expect(buffer.extrapolating, isTrue);
  });

  test('angle interpolation takes the short way round', () {
    final buffer = SnapshotBuffer()..interpDelayMs = 50;
    // 6.2 rad is just under a full turn; 0.1 rad is just past it.
    buffer
      ..add(snap(t: 0, x: 0, angle: 6.2))
      ..add(snap(t: 100, x: 0, angle: 0.1))
      ..advance(0);

    final angle = buffer.sampleAll()['bird']!.angle;
    // Halfway is a small step forward past 2π, not most of a turn backwards.
    expect(angle, closeTo(6.2 + (0.1 + 2 * math.pi - 6.2) / 2, 1e-9));
  });

  test('a restarted host timeline is dropped rather than interpolated across',
      () {
    final buffer = SnapshotBuffer()..interpDelayMs = 50;
    buffer
      ..add(snap(t: 5000, x: 30))
      ..advance(0);
    expect(buffer.renderTimeMs, closeTo(4950, 1e-9));

    // Re-calibration restarts the sim clock at 0.
    buffer
      ..add(snap(t: 0, x: 0))
      ..add(snap(t: 100, x: 1))
      ..advance(0);

    expect(buffer.bufferedSnapshots, 2);
    expect(buffer.renderTimeMs, closeTo(50, 1e-9));
    expect(buffer.sampleAll()['bird']!.x, closeTo(0.5, 1e-9));
  });

  test('two phones with different frame pacing agree on where the bird is', () {
    // This is the seam property, stated as a test. Both phones consume the same
    // snapshot stream on the same delay, but render on their own frame clocks.
    // If they disagreed by more than a fraction of a millimetre, the bird would
    // visibly step as it crossed the gap.
    final phoneA = SnapshotBuffer()..interpDelayMs = 80;
    final phoneB = SnapshotBuffer()..interpDelayMs = 80;

    const stepMs = 1000 / 60;
    const speed = 20.0; // world units/s — a hard launch

    for (var frame = 0; frame < 240; frame++) {
      final t = frame * stepMs;
      final s = snap(t: t, x: speed * t / 1000, vx: speed);
      phoneA.add(s);
      phoneB.add(s);

      // A renders once per snapshot; B renders twice as often, unevenly.
      phoneA.advance(stepMs);
      phoneB
        ..advance(stepMs * 0.35)
        ..advance(stepMs * 0.65);
    }

    final a = phoneA.sampleAll()['bird']!;
    final b = phoneB.sampleAll()['bird']!;

    // Identical streams, identical elapsed time: the render clock is built from
    // accumulated local time, so frame pacing cannot move it at all.
    expect((a.x - b.x).abs(), lessThan(1e-9));
    expect(phoneA.extrapolating, isFalse);
    expect(phoneB.extrapolating, isFalse);
  });

  test('the render clock stays the interpolation delay behind the host', () {
    final buffer = SnapshotBuffer()..interpDelayMs = 80;
    const stepMs = 1000 / 60;

    for (var frame = 0; frame < 240; frame++) {
      buffer
        ..add(snap(t: frame * stepMs, x: 0))
        ..advance(stepMs);
    }

    final newest = 239 * stepMs;
    // Tracking, not drifting: a couple of frames of slack is fine, a growing
    // gap would mean the buffer never converges.
    expect(buffer.renderTimeMs, closeTo(newest - 80, 2 * stepMs));
  });

  test('a hard stall resyncs instead of crawling back', () {
    final buffer = SnapshotBuffer()..interpDelayMs = 80;
    buffer
      ..add(snap(t: 0, x: 0))
      ..advance(0)
      // App suspended for two seconds, then snapshots resume far ahead.
      ..add(snap(t: 2000, x: 40))
      ..advance(16);

    expect(buffer.renderTimeMs, closeTo(1936, 1e-9));
  });

  test('phones disagree by less than the jitter between them', () {
    // The honest version of the previous test: real phones receive the same
    // snapshot at slightly different moments. Disagreement should stay on the
    // order of that jitter, not accumulate.
    final phoneA = SnapshotBuffer()..interpDelayMs = 80;
    final phoneB = SnapshotBuffer()..interpDelayMs = 80;

    const stepMs = 1000 / 60;
    const speed = 20.0;
    final jitter = [0.0, 4.0, 1.5, 9.0, 0.5, 6.0];

    for (var frame = 0; frame < 240; frame++) {
      final t = frame * stepMs;
      final s = snap(t: t, x: speed * t / 1000, vx: speed);

      phoneA.add(s);
      phoneA.advance(stepMs);

      // B receives the same snapshot a few milliseconds late.
      final late = jitter[frame % jitter.length];
      phoneB.advance(late);
      phoneB.add(s);
      phoneB.advance(stepMs - late);
    }

    final a = phoneA.sampleAll()['bird']!;
    final b = phoneB.sampleAll()['bird']!;

    // 9ms of jitter at 20cm/s is 1.8mm of travel; the clocks must not amplify
    // it. 0.2 world units = 2mm.
    expect((a.x - b.x).abs(), lessThan(0.2));
  });
}
