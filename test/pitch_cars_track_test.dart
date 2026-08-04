import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/pitch_cars/track.dart';

void main() {
  group('PitchTrack — an open two-point track', () {
    final track = PitchTrack(
      waypoints: const [Waypoint(0, 0), Waypoint(10, 0)],
      widthWorld: 2,
      closed: false,
    );

    test('length is the straight-line distance', () {
      expect(track.length, closeTo(10, 1e-9));
    });

    test('a point on the centerline is on track', () {
      expect(track.isOnTrack(5, 0), isTrue);
    });

    test('a point just inside the width is on track', () {
      expect(track.isOnTrack(5, 0.9), isTrue);
    });

    test('a point outside the width is off track', () {
      expect(track.isOnTrack(5, 1.1), isFalse);
    });

    test('progress runs from 0 at the start to length at the end', () {
      expect(track.progressAt(0, 0), closeTo(0, 1e-9));
      expect(track.progressAt(10, 0), closeTo(10, 1e-9));
      expect(track.progressAt(5, 0), closeTo(5, 1e-9));
    });

    test('pointAtArclength is the inverse of progressAt on the centerline', () {
      final p = track.pointAtArclength(3);
      expect(p.x, closeTo(3, 1e-9));
      expect(p.y, closeTo(0, 1e-9));
    });

    test('tangentAt points along the track', () {
      final t = track.tangentAt(5);
      expect(t.x, closeTo(1, 1e-6));
      expect(t.y, closeTo(0, 1e-6));
    });
  });

  group('PitchTrack — a closed square loop', () {
    final track = PitchTrack(
      waypoints: const [
        Waypoint(-5, -5),
        Waypoint(5, -5),
        Waypoint(5, 5),
        Waypoint(-5, 5),
      ],
      widthWorld: 2,
      closed: true,
    );

    test('length includes the closing segment back to the first point', () {
      expect(track.length, closeTo(40, 1e-9));
    });

    test('the ring is on track; its hollow centre is not', () {
      expect(track.isOnTrack(0, -5), isTrue); // on the bottom edge
      expect(track.isOnTrack(0, 0), isFalse); // the donut hole
    });

    test('a point well outside the ring is off track', () {
      expect(track.isOnTrack(0, -20), isFalse);
    });

    test('progress wraps: the point after the last waypoint is near the start',
        () {
      // Just past the last waypoint, heading back toward the first.
      final p = track.pointAtArclength(39.5);
      expect(p.x, closeTo(-4.5, 1e-6));
      expect(p.y, closeTo(5, 1e-6));
    });
  });
}
