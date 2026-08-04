import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_links.dart';
import 'package:multiscreen_slingshot/sdk/layout/layouts.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart' show PhoneSlice;
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/coverage_map.dart'
    show ScreenRect;

/// Coloured stripes marking which screen edge meets which neighbour.
///
/// All of this falls out of the compiled geometry, computed once on the host —
/// so these tests are the only place the rule is checked, and every phone draws
/// whatever comes out of here.
PhoneSpec phone(
  String id, {
  double widthMm = 68.58,
  double heightMm = 152.4,
  double bezelMm = 3,
}) => PhoneSpec(
  phoneId: id,
  label: 'phone $id',
  widthMm: widthMm,
  heightMm: heightMm,
  bezelMm: bezelMm,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: widthMm * 400 / 25.4,
  activePxHeight: heightMm * 400 / 25.4,
);

BoardLayout row(List<PhoneSpec> phones) =>
    const BoardCompiler().compile(Layouts.row(phones), LobbyInfo(phones));

BoardLayout column(List<PhoneSpec> phones) =>
    const BoardCompiler().compile(Layouts.column(phones), LobbyInfo(phones));

BoardLayout ring(List<PhoneSpec> phones) =>
    const BoardCompiler().compile(Layouts.circle(phones), LobbyInfo(phones));

double _length(EdgeMarker m) =>
    math.sqrt(math.pow(m.x2 - m.x1, 2) + math.pow(m.y2 - m.y1, 2));

void main() {
  group('a row', () {
    test('gives each join two stripes sharing a colour', () {
      final board = row([phone('p1'), phone('p2')]);
      expect(board.links, hasLength(2));

      final a = board.links.firstWhere((l) => l.phoneId == 'p1');
      final b = board.links.firstWhere((l) => l.phoneId == 'p2');

      // The whole point: matching colours to line up.
      expect(a.colorIndex, b.colorIndex);
      expect(a.partnerId, 'p2');
      expect(b.partnerId, 'p1');
    });

    test('the stripes sit on the two facing edges, one bezel gap apart', () {
      final board = row([phone('p1'), phone('p2')]);
      final left = board.forPhone('p1')!.viewport;
      final right = board.forPhone('p2')!.viewport;

      final a = board.links.firstWhere((l) => l.phoneId == 'p1');
      final b = board.links.firstWhere((l) => l.phoneId == 'p2');

      // Vertical stripes on the inner edges.
      expect(a.x1, closeTo(left.right, 1e-9));
      expect(a.x2, closeTo(left.right, 1e-9));
      expect(b.x1, closeTo(right.left, 1e-9));
      expect(b.x2, closeTo(right.left, 1e-9));
      expect(b.x1 - a.x1, closeTo(0.6, 1e-6));
    });

    test('three phones give two joins, in different colours', () {
      final board = row([phone('p1'), phone('p2'), phone('p3')]);
      expect(board.links, hasLength(4));

      final colours = board.links.map((l) => l.colorIndex).toSet();
      expect(colours, hasLength(2), reason: 'two joins, two colours');

      // The middle phone carries one of each, on opposite edges.
      final middle = board.links.where((l) => l.phoneId == 'p2').toList();
      expect(middle, hasLength(2));
      expect(middle.map((l) => l.colorIndex).toSet(), hasLength(2));
      expect(middle.map((l) => l.partnerId).toSet(), {'p1', 'p3'});
    });
  });

  group('a column', () {
    test('stripes run horizontally, across the touching edges', () {
      final board = column([phone('p1'), phone('p2')]);
      expect(board.links, hasLength(2));

      for (final link in board.links) {
        // Horizontal: same y at both ends.
        expect(link.y1, closeTo(link.y2, 1e-9));
        expect((link.x2 - link.x1).abs(), greaterThan(0));
      }

      final upper = board.forPhone('p1')!.viewport;
      final a = board.links.firstWhere((l) => l.phoneId == 'p1');
      expect(a.y1, closeTo(upper.bottom, 1e-9));
    });

    test('the ball bin stack chains its phones, neighbour to neighbour', () {
      final board = column([phone('p1'), phone('p2'), phone('p3')]);

      // Top and bottom each have one stripe; the middle has two. Nobody is
      // joined to a phone two places away.
      final byPhone = <String, int>{};
      for (final l in board.links) {
        byPhone[l.phoneId] = (byPhone[l.phoneId] ?? 0) + 1;
      }
      expect(byPhone['p1'], 1);
      expect(byPhone['p2'], 2);
      expect(byPhone['p3'], 1);

      expect(
        board.links.any((l) =>
            (l.phoneId == 'p1' && l.partnerId == 'p3') ||
            (l.phoneId == 'p3' && l.partnerId == 'p1')),
        isFalse,
        reason: 'the middle phone is in the way; that is not a join',
      );
    });
  });

  group('mismatched phones', () {
    test('a stripe covers only the overlap, not the whole edge', () {
      // A row lays phones on their sides, so the edges that meet are their
      // *short* sides — vary that, not the long one, or both footprints come
      // out the same depth and there is no mismatch to test.
      final deep = phone('deep', widthMm: 80, heightMm: 150);
      final shallow = phone('shallow', widthMm: 50, heightMm: 150);
      final board = row([deep, shallow]);

      final deepRect = board.forPhone('deep')!.viewport;
      final shallowRect = board.forPhone('shallow')!.viewport;
      final overlap = math.min(deepRect.bottom, shallowRect.bottom) -
          math.max(deepRect.top, shallowRect.top);

      for (final link in board.links) {
        expect(_length(link), closeTo(overlap, 1e-6));
        // Which is the shallow phone's depth, and shorter than the deep one's.
        expect(_length(link), closeTo(shallowRect.height, 1e-6));
        expect(_length(link), lessThan(deepRect.height - 1e-6));
      }
    });

    test('both ends of a join are the same length', () {
      final board = row([
        phone('a', widthMm: 80),
        phone('b', widthMm: 50),
      ]);
      final lengths = board.links.map(_length).toSet();
      expect(lengths, hasLength(1));
    });
  });

  group('a ring', () {
    test('has no joins, so every phone gets one inward stripe instead', () {
      final board = ring([phone('p1'), phone('p2'), phone('p3')]);

      expect(board.links, hasLength(3));
      expect(board.links.every((l) => l.partnerId == null), isTrue,
          reason: 'nothing is touching in a ring');
      expect(board.links.map((l) => l.phoneId).toSet(),
          {'p1', 'p2', 'p3'});
    });

    test('they all share one colour', () {
      final board = ring([for (var i = 0; i < 5; i++) phone('p$i')]);
      expect(board.links.map((l) => l.colorIndex).toSet(), hasLength(1));
    });

    test('each stripe is on the edge facing the middle', () {
      final board = ring([for (var i = 0; i < 5; i++) phone('p$i')]);
      final phones = board.phones;
      final midX =
          phones.map((p) => p.worldCenterX).reduce((a, b) => a + b) /
              phones.length;
      final midY =
          phones.map((p) => p.worldCenterY).reduce((a, b) => a + b) /
              phones.length;

      for (final link in board.links) {
        final me = board.forPhone(link.phoneId)!;
        final stripeMidX = (link.x1 + link.x2) / 2;
        final stripeMidY = (link.y1 + link.y2) / 2;

        // The stripe's middle must be nearer the ring centre than the screen's
        // own middle is — that is what "on the inward side" means.
        final stripeToMid = math.sqrt(
            math.pow(stripeMidX - midX, 2) + math.pow(stripeMidY - midY, 2));
        final screenToMid = math.sqrt(
            math.pow(me.worldCenterX - midX, 2) +
                math.pow(me.worldCenterY - midY, 2));
        expect(stripeToMid, lessThan(screenToMid),
            reason: '${link.phoneId} marked its outward edge');
      }
    });

    test('the stripe runs the length of an actual screen edge', () {
      final board = ring([for (var i = 0; i < 4; i++) phone('p$i')]);
      for (final link in board.links) {
        final me = board.forPhone(link.phoneId)!;
        final short = me.halfWidth * 2;
        final long = me.halfHeight * 2;
        // It is one edge or the other, not a diagonal.
        expect(
          _length(link),
          anyOf(closeTo(short, 1e-6), closeTo(long, 1e-6)),
        );
      }
    });
  });

  group('one phone alone', () {
    test('has nothing to line up with, so no stripes', () {
      final board = row([phone('p1')]);
      expect(board.links, isEmpty);
    });
  });

  test('the same board always produces the same colours', () {
    final phones = [phone('p1'), phone('p2'), phone('p3')];
    final first = row(phones).links;
    final second = row(phones).links;

    // Two phones computing this would agree — but they never have to, because
    // the host computes it once and sends it. This pins the determinism the
    // design leans on either way.
    expect(
      first.map((l) => '${l.phoneId}:${l.colorIndex}').toList(),
      second.map((l) => '${l.phoneId}:${l.colorIndex}').toList(),
    );
  });

  test('BoardLinks is the only place this is decided', () {
    // A guard against the logic being reimplemented in a widget: the compiler
    // fills `links`, and everything downstream just draws them.
    final board = row([phone('p1'), phone('p2')]);
    expect(
      board.links.map((l) => l.toJson()).toList(),
      BoardLinks.of(board.slices).map((l) => l.toJson()).toList(),
    );
  });

  group('phones that touch exactly', () {
    // A real four-device table produced one join and two grey orphans, so every
    // stripe came out colour 0 — three identical red lines. The pairs that
    // failed reported a gap of -23.57 between screens whose edges were, on
    // paper, in the same place. Zero-bezel devices lay flush, the two edges
    // landed one bit apart, and the branch that guessed which phone came first
    // guessed wrong: it measured from the far edges instead of the near ones.
    test('join even when a rounding error puts the edges out of order', () {
      // Deliberately built so the upper screen's bottom edge sits a billionth
      // of a unit *past* the lower screen's top edge — the losing coin flip,
      // made deterministic.
      final upper = PhoneSlice(
        'p1',
        const ScreenRect(centerX: 0, centerY: 5 + 1e-9, width: 20, height: 10),
      );
      final lower = PhoneSlice(
        'p2',
        const ScreenRect(centerX: 0, centerY: 15, width: 20, height: 10),
      );

      final verdict = BoardLinks.explain([upper, lower]).single;
      expect(verdict.joined, isTrue, reason: 'these two are touching');
      expect(verdict.axis, 'stacked');
      expect(verdict.gap.abs(), lessThan(1e-6));

      // And the stripes go on the edges that meet, not the outer edges.
      for (final marker in BoardLinks.of([upper, lower])) {
        expect(marker.y1, closeTo(10, 1e-6));
        expect(marker.isJoin, isTrue);
      }
    });

    test('a zero-bezel stack gives every pair its own colour', () {
      // The audited table: a phone reporting a 3mm bezel above three desktop
      // windows reporting none. Flush edges throughout.
      final board = column([
        phone('p1', widthMm: 65.31, heightMm: 133.89),
        phone('p2', widthMm: 117.83, heightMm: 207.08, bezelMm: 0),
        phone('p3', widthMm: 117.83, heightMm: 207.08, bezelMm: 0),
        phone('p4', widthMm: 117.83, heightMm: 207.08, bezelMm: 0),
      ]);

      expect(board.links.where((l) => !l.isJoin), isEmpty,
          reason: 'nothing in a stack should fall back to an inward stripe');
      expect(board.links.map((l) => l.colorIndex).toSet(), {0, 1, 2},
          reason: 'three joins, three colours — not three of the same');
    });
  });
}
