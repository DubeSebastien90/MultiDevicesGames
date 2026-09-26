import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/arena/arena_game.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_game.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/layouts.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';
import 'package:multiscreen_slingshot/sdk/model/world_rect.dart';
import 'package:multiscreen_slingshot/sdk/physics/play_area.dart';

/// Portrait panel: width is the short edge. On its side this one covers
/// 152.4 x 68.58 mm of board.
PhoneSpec phone(
  String id, {
  double widthMm = 68.58,
  double heightMm = 152.4,
  double bezelMm = 3,
}) =>
    PhoneSpec(
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

List<PhoneSpec> phones(int n) => [for (var i = 1; i <= n; i++) phone('p$i')];

void main() {
  const compiler = BoardCompiler();

  Map<String, WorldRect> screensOf(BoardLayout board) => {
        for (final s in board.slices) s.phoneId: s.screen.bounds,
      };

  group('Layouts.brick', () {
    test('three phones: two above, the third centred across their join', () {
      final lobby = LobbyInfo(phones(3));
      final board = compiler.compile(Layouts.brick(lobby.phones), lobby);
      final s = screensOf(board);

      // p1 and p2 end to end, 0.6 of bezel between them.
      expect(s['p2']!.left - s['p1']!.right, closeTo(0.6, 1e-6));
      expect(s['p1']!.top, closeTo(s['p2']!.top, 1e-6));

      // p3 below, one seam down, and centred on the join above it.
      expect(s['p3']!.top - s['p1']!.bottom, closeTo(0.6, 1e-6));
      final join = (s['p1']!.right + s['p2']!.left) / 2;
      expect(s['p3']!.centerX, closeTo(join, 1e-6));
    });

    test('five and seven: one more on top, rows centred, bricks on joins', () {
      for (final n in [5, 7]) {
        final lobby = LobbyInfo(phones(n));
        final board = compiler.compile(Layouts.brick(lobby.phones), lobby);
        final s = screensOf(board);
        final top = (n + 1) ~/ 2;

        final upper = [for (var i = 1; i <= top; i++) s['p$i']!];
        final lower = [for (var i = top + 1; i <= n; i++) s['p$i']!];
        expect(lower, hasLength(top - 1));

        final upperMid = (upper.first.left + upper.last.right) / 2;
        final lowerMid = (lower.first.left + lower.last.right) / 2;
        expect(lowerMid, closeTo(upperMid, 1e-6), reason: '$n phones');

        for (var c = 0; c < lower.length; c++) {
          final join = (upper[c].right + upper[c + 1].left) / 2;
          expect(lower[c].centerX, closeTo(join, 1e-6),
              reason: '$n phones, bottom ${c + 1}');
          expect(lower[c].top - upper[c].bottom, closeTo(0.6, 1e-6));
        }
      }
    });

    test('mismatched depths still meet flush at the seam', () {
      final lobby = LobbyInfo([
        phone('p1', widthMm: 60, heightMm: 130),
        phone('p2'),
        phone('p3', widthMm: 75, heightMm: 160),
      ]);
      final board = compiler.compile(Layouts.brick(lobby.phones), lobby);
      final s = screensOf(board);

      expect(s['p1']!.bottom, closeTo(s['p2']!.bottom, 1e-6));
      expect(s['p3']!.top - s['p2']!.bottom, closeTo(0.6, 1e-6));
    });

    test('refuses a single phone', () {
      expect(() => Layouts.brick(phones(1)), throwsA(anything));
    });
  });

  group('Layouts.shortestLast', () {
    test('moves only the shortest long edge, keeping the others in order', () {
      final lobby = [
        phone('a'),
        phone('small', widthMm: 60, heightMm: 130),
        phone('c', widthMm: 75, heightMm: 160),
      ];
      expect(
        Layouts.shortestLast(lobby).map((p) => p.phoneId),
        ['a', 'c', 'small'],
      );
    });
  });

  group('Arena and Dodgeball boards', () {
    final games = {'arena': const ArenaGame(), 'dodgeball': const DodgeballGame()};

    test('three phones put the smallest below, across the join', () {
      for (final MapEntry(key: name, value: game) in games.entries) {
        final lobby = LobbyInfo([
          phone('small', widthMm: 60, heightMm: 130),
          phone('p2'),
          phone('p3'),
        ]);
        final board = compiler.compile(game.planBoard(lobby), lobby);
        final s = screensOf(board);

        expect(s['small']!.top, greaterThan(s['p2']!.bottom), reason: name);
        final join = (s['p2']!.right + s['p3']!.left) / 2;
        expect(s['small']!.centerX, closeTo(join, 1e-6), reason: name);
      }
    });

    test('five and seven are bricks, four, six and eight stay grids', () {
      for (final MapEntry(key: name, value: game) in games.entries) {
        for (final n in [2, 3, 4, 5, 6, 7, 8]) {
          final lobby = LobbyInfo(phones(n));
          final board = compiler.compile(game.planBoard(lobby), lobby);
          final tops = {
            for (final r in screensOf(board).values) r.top.toStringAsFixed(4),
          };
          final rows = n == 2 ? 1 : 2;
          expect(tops, hasLength(rows), reason: '$name, $n phones');

          final firstRow = screensOf(board)
              .values
              .where((r) => r.top.toStringAsFixed(4) == tops.first)
              .length;
          expect(firstRow, n == 2 ? 2 : (n + 1) ~/ 2,
              reason: '$name, $n phones');
        }
      }
    });
  });

  group('PlayArea on a brick', () {
    late BoardLayout board;
    late PlayArea area;
    late Map<String, WorldRect> s;

    setUp(() {
      final lobby = LobbyInfo(phones(3));
      board = compiler.compile(Layouts.brick(lobby.phones), lobby);
      area = PlayArea.of(board.coverage);
      s = screensOf(board);
    });

    test('the corners beside the phone below are walled off', () {
      final belowP1 = (x: s['p1']!.left + 1, y: s['p3']!.centerY);
      expect(area.contains(belowP1.x, belowP1.y), isFalse);

      final held = area.clamp(belowP1.x, belowP1.y, 0.5);
      expect(area.contains(held.x, held.y), isTrue);
    });

    test('the seams, and the square where they meet, are all playable', () {
      final joinX = (s['p1']!.right + s['p2']!.left) / 2;
      final seamY = (s['p1']!.bottom + s['p3']!.top) / 2;
      expect(area.contains(joinX, s['p1']!.centerY), isTrue);
      expect(area.contains(s['p3']!.left + 1, seamY), isTrue);
      expect(area.contains(joinX, seamY), isTrue, reason: 'the T junction');
    });

    test('a player walks from every screen to every other without leaving', () {
      final centres = [for (final r in s.values) (x: r.centerX, y: r.centerY)];
      for (final a in centres) {
        for (final b in centres) {
          for (var t = 0.0; t <= 1.0; t += 0.01) {
            final x = a.x + (b.x - a.x) * t;
            final y = a.y + (b.y - a.y) * t;
            final held = area.clamp(x, y, 0.5);
            expect(area.contains(held.x, held.y), isTrue);
          }
        }
      }
      // The straight line from p1 to p3 crosses a seam, not a wall.
      final p1 = s['p1']!;
      final p3 = s['p3']!;
      final x = (p1.right - 2 + p3.left + 2) / 2;
      for (var y = p1.centerY; y <= p3.centerY; y += 0.05) {
        expect(area.contains(x, y), isTrue, reason: 'y=$y');
      }
    });

    test('the middle of a 2x2 grid is no longer a hole', () {
      final lobby = LobbyInfo(phones(4));
      final grid = compiler.compile(Layouts.grid(lobby.phones, rows: 2), lobby);
      final g = screensOf(grid);
      final gridArea = PlayArea.of(grid.coverage);
      final x = (g['p1']!.right + g['p2']!.left) / 2;
      final y = (g['p1']!.bottom + g['p3']!.top) / 2;
      expect(gridArea.contains(x, y), isTrue);
    });
  });
}
