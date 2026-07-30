import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/host/layout_solver.dart';
import 'package:multiscreen_slingshot/model/device_metrics.dart';

/// A landscape phone: [widthMm] across, [heightMm] tall, at [dpi].
DeviceMetrics phone({
  required double widthMm,
  required double heightMm,
  required double dpi,
  double bezelMm = 3,
  String label = 'phone',
}) => DeviceMetrics(
  activePxWidth: widthMm / 25.4 * dpi,
  activePxHeight: heightMm / 25.4 * dpi,
  widthMm: widthMm,
  heightMm: heightMm,
  bezelMm: bezelMm,
  devicePixelRatio: 3,
  label: label,
);

void main() {
  const solver = LayoutSolver();
  // The v1 scale: 1 world unit = 1cm.
  const mmToWorld = 0.1;

  group('two identical phones', () {
    final metrics = phone(widthMm: 152.4, heightMm: 68.58, dpi: 400);
    final board = solver.solve([
      CalibratedPhone('p1', metrics),
      CalibratedPhone('p2', metrics),
    ]);

    test('left phone starts at the world origin', () {
      expect(board.phones[0].worldOffsetX, 0);
      expect(board.phones[0].worldOffsetY, 0);
    });

    test('the gap between active areas is both bezels', () {
      // 3mm + 3mm = 6mm = 0.6 world units.
      expect(board.phones[1].worldOffsetX, closeTo(15.24 + 0.6, 1e-9));
    });

    test('top edges are aligned', () {
      expect(board.phones.every((p) => p.worldOffsetY == 0), isTrue);
    });

    test('the board spans both screens plus the gap', () {
      expect(board.board.width, closeTo(15.24 * 2 + 0.6, 1e-9));
      expect(board.board.height, closeTo(6.858, 1e-9));
    });

    test('the gap is the only dead zone, and it is really dead', () {
      final seams = board.coverage.seamRects();
      expect(seams, hasLength(1));
      expect(seams.single.left, closeTo(15.24, 1e-9));
      expect(seams.single.width, closeTo(0.6, 1e-9));

      // Mid-gap is not backed by a screen; both screens are.
      expect(board.coverage.isCovered(15.54, 3), isFalse);
      expect(board.coverage.isCovered(1, 3), isTrue);
      expect(board.coverage.isCovered(20, 3), isTrue);
    });
  });

  group('per-phone transform', () {
    final board = solver.solve([
      CalibratedPhone('p1', phone(widthMm: 152.4, heightMm: 68.58, dpi: 400)),
      CalibratedPhone('p2', phone(widthMm: 152.4, heightMm: 68.58, dpi: 400)),
    ]);

    test('touch and render transforms are exact inverses', () {
      // If these ever drift apart, a finger and the thing it grabs stop
      // agreeing — and so do two phones about where the bird is.
      for (final p in board.phones) {
        for (final px in const [0.0, 137.0, 1200.0, 2400.0]) {
          final world = p.physicalPxToWorld(px, px / 2);
          final back = p.worldToPhysicalPx(world.x, world.y);
          expect(back.x, closeTo(px, 1e-9));
          expect(back.y, closeTo(px / 2, 1e-9));
        }
      }
    });

    test("the right phone's left pixel is one gap past the left phone's edge",
        () {
      final left = board.phones[0];
      final right = board.phones[1];

      final leftEdge = left.physicalPxToWorld(left.activePxWidth, 0);
      final rightEdge = right.physicalPxToWorld(0, 0);

      // 6mm of bezel between the last lit pixel and the first one.
      expect(rightEdge.x - leftEdge.x, closeTo(0.6, 1e-9));
    });

    test('a viewport covers exactly its own screen', () {
      final v = board.phones[1].viewport;
      expect(v.left, closeTo(15.84, 1e-9));
      expect(v.width, closeTo(15.24, 1e-9));
      expect(v.height, closeTo(6.858, 1e-9));
    });
  });

  test('phones of different density draw the world at the same physical size',
      () {
    // Same glass, wildly different resolutions. This is the case the whole
    // mm-based pipeline exists for.
    final board = solver.solve([
      CalibratedPhone('p1', phone(widthMm: 152.4, heightMm: 68.58, dpi: 400)),
      CalibratedPhone('p2', phone(widthMm: 152.4, heightMm: 68.58, dpi: 267)),
    ]);

    expect(
      board.phones[0].viewport.width,
      closeTo(board.phones[1].viewport.width, 1e-9),
    );
    // One world unit is 1cm of real glass on both, so the pixels-per-unit differ
    // by exactly the density ratio.
    expect(
      board.phones[0].dpi / board.phones[1].dpi,
      closeTo(400 / 267, 1e-9),
    );
    expect(board.mmToWorld, mmToWorld);
  });

  test('the board hugs the shortest screen so there are no corner dead zones',
      () {
    final board = solver.solve([
      CalibratedPhone('p1', phone(widthMm: 150, heightMm: 70, dpi: 400)),
      CalibratedPhone('p2', phone(widthMm: 150, heightMm: 62, dpi: 400)),
    ]);

    expect(board.board.height, closeTo(6.2, 1e-9));

    // Every dead zone is a real bezel gap; nothing is dead merely because the
    // board was defined as a bounding box.
    final seams = board.coverage.seamRects();
    expect(seams, hasLength(1));
    expect(seams.single.width, closeTo(0.6, 1e-9));
  });

  test('a solo phone gets the whole board', () {
    final board = solver.solve([
      CalibratedPhone('p1', phone(widthMm: 152.4, heightMm: 68.58, dpi: 400)),
    ]);
    expect(board.coverage.seamRects(), isEmpty);
    expect(board.board.width, closeTo(15.24, 1e-9));
    expect(board.phones.single.total, 1);
  });

  test('phones keep their listed order, which is the physical arrangement', () {
    final board = solver.solve([
      CalibratedPhone('a', phone(widthMm: 100, heightMm: 60, dpi: 400)),
      CalibratedPhone('b', phone(widthMm: 140, heightMm: 60, dpi: 400)),
      CalibratedPhone('c', phone(widthMm: 120, heightMm: 60, dpi: 400)),
    ]);

    expect(board.phones.map((p) => p.phoneId), ['a', 'b', 'c']);
    expect(board.phones[0].worldOffsetX, closeTo(0, 1e-9));
    expect(board.phones[1].worldOffsetX, closeTo(10.0 + 0.6, 1e-9));
    expect(board.phones[2].worldOffsetX, closeTo(10.6 + 14.0 + 0.6, 1e-9));
    expect(board.phones[2].index, 2);
  });
}
