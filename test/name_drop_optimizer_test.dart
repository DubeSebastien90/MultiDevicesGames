import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/ball_bin/ball_bin_game.dart';
import 'package:multiscreen_slingshot/games/hot_potato/hot_potato_game.dart';
import 'package:multiscreen_slingshot/games/slingshot/slingshot_game.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/name_drop_optimizer.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';

/// Pixels are square and dpi comes from the width, so the millimetres have to
/// agree with the pixel aspect ratio or the phone is one no shop sells.
PhoneSpec spec(String id, double widthMm) => PhoneSpec(
  phoneId: id,
  label: 'phone $id',
  widthMm: widthMm,
  heightMm: widthMm * 2400 / 1080,
  bezelMm: 3,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: 1080,
  activePxHeight: 2400,
);

/// Which way each phone ends up facing, in plan order.
List<double> turns(BoardPlan plan) => [
  for (final p in plan.placements) p.turnDeg,
];

void main() {
  group('phones stacked tops-together are turned apart', () {
    // Ball Bin stacks phones lying sideways, so each top edge is a vertical
    // segment down one side and neighbours' segments are collinear, end to end,
    // a few millimetres apart. Both phones facing the same way is the trigger.
    //
    // The size difference is the whole point of the sweep. Scoring the *corners*
    // of the top edges made the measured distance grow with how unlike the two
    // phones were — 9 mm for a close pair, 23 mm for a far one — so the check
    // passed at 15 mm and quietly stopped protecting anyone as soon as the table
    // was mismatched. An SE beside a Pro Max is an ordinary pair of phones.
    for (final wide in [66.0, 70.0, 74.0, 77.0, 80.0, 95.0]) {
      test('a 60 mm phone under a ${wide.round()} mm one', () {
        final lobby = LobbyInfo([spec('p1', 60), spec('p2', wide)]);
        final raw = const BallBinGame().planBoard(lobby);

        expect(turns(raw).toSet(), hasLength(1),
            reason: 'the layout is meant to hand both phones the same turn — '
                'that is the arrangement this optimizer exists to fix');

        final fixed = turns(NameDropOptimizer.optimize(raw, lobby));
        expect(fixed.toSet(), hasLength(2),
            reason: 'both phones still face the same way, so their tops are '
                'still against each other');
      });
    }
  });

  group('phones that are already safe are left alone', () {
    // The cost of getting this wrong is asking somebody to put their phone on
    // the table upside down for no reason, so it has to be earned every time.
    test('a row does not need anybody to turn around', () {
      // Sideways in a row: each top edge is a short end, and neighbours are a
      // whole phone length apart along the row.
      final lobby = LobbyInfo([
        spec('p1', 58),
        spec('p2', 68),
        spec('p3', 77),
      ]);
      final raw = const SlingshotGame().planBoard(lobby);

      expect(
        NameDropOptimizer.optimize(raw, lobby).placements.map((p) => p.turnDeg),
        turns(raw),
      );
    });

    test('a ring does not either', () {
      // Every phone faces its own player, so no two tops point at each other.
      final lobby = LobbyInfo([
        spec('p1', 58),
        spec('p2', 68),
        spec('p3', 77),
        spec('p4', 62),
      ]);
      final raw = const HotPotatoGame().planBoard(lobby);

      expect(
        NameDropOptimizer.optimize(raw, lobby).placements.map((p) => p.turnDeg),
        turns(raw),
      );
    });

    test('one phone has nothing to be near', () {
      final lobby = LobbyInfo([spec('p1', 68)]);
      final raw = const SlingshotGame().planBoard(lobby);

      expect(NameDropOptimizer.optimize(raw, lobby), same(raw),
          reason: 'a plan that cannot be improved should come back untouched');
    });
  });

  test('the greedy path is walked when there are too many to enumerate', () {
    // Nine phones: past the point where 2^n states are worth visiting, so a
    // different search runs. No game in the catalogue seats nine, which is
    // exactly why it is worth a test — nothing else exercises it.
    final specs = [
      for (var i = 0; i < 9; i++) spec('p${i + 1}', 58 + i * 4.0),
    ];
    // A stack, built here rather than by a game, since none of them fits nine.
    var y = 0.0;
    final placements = <PhonePlacement>[];
    for (final s in specs) {
      y += s.widthMm / 2;
      placements.add(PhonePlacement(s.phoneId, xMm: 100, yMm: y, turnDeg: 90));
      y += s.widthMm / 2 + 6;
    }

    final raw = BoardPlan(placements, instruction: 'stack', allowGaps: true);
    final fixed = NameDropOptimizer.optimize(raw, LobbyInfo(specs));

    final order = fixed.placements.toList()
      ..sort((a, b) => a.yMm.compareTo(b.yMm));
    for (var i = 1; i < order.length; i++) {
      expect(order[i].turnDeg, isNot(order[i - 1].turnDeg),
          reason: '${order[i - 1].phoneId} and ${order[i].phoneId} are stacked '
              'and face the same way, so their tops touch');
    }
  });

  test('a whole stack is untangled, not just the closest pair', () {
    // Five phones, every one a different size: four neighbouring pairs, and the
    // old scoring saw only the ones whose phones happened to be alike.
    final lobby = LobbyInfo([
      spec('p1', 58),
      spec('p2', 66),
      spec('p3', 71),
      spec('p4', 79),
      spec('p5', 88),
    ]);
    final raw = const BallBinGame().planBoard(lobby);
    final fixed = NameDropOptimizer.optimize(raw, lobby);

    // Bottom to top, no two neighbours may face the same way — that is what
    // "no two tops together" reduces to in a stack.
    final order = fixed.placements.toList()
      ..sort((a, b) => a.yMm.compareTo(b.yMm));
    for (var i = 1; i < order.length; i++) {
      expect(order[i].turnDeg, isNot(order[i - 1].turnDeg),
          reason: '${order[i - 1].phoneId} and ${order[i].phoneId} are stacked '
              'and face the same way, so their tops touch');
    }
  });
}
