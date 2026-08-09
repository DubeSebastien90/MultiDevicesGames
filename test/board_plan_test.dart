import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/contract/sim.dart' show PhoneSlice;
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/model/phone_layout.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_links.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/layouts.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';

/// The layout half of the SDK contract: a game decides where phones go, the
/// platform compiles that into a board or refuses.
///
/// A panel is always described **portrait** — width is the short edge — because
/// the app is locked portrait and how a phone lies on the table is the game's
/// decision, not the device's. So this is a 68.58 x 152.4mm phone, which turned
/// on its side covers 152.4 x 68.58 of a board.
PhoneSpec phone(
  String id, {
  double widthMm = 68.58, // short edge, 400 dpi
  double heightMm = 152.4, // long edge
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

LobbyInfo lobbyOf(List<PhoneSpec> phones) => LobbyInfo(phones);

void main() {
  const compiler = BoardCompiler();

  group('Layouts.row reproduces the old strip exactly', () {
    test('two phones, side by side, top edges flush', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      final board = compiler.compile(Layouts.row(lobby.phones), lobby);

      // The numbers the original slingshot board was tuned against.
      expect(board.board.width, closeTo(15.24 * 2 + 0.6, 1e-9));
      expect(board.board.height, closeTo(6.858, 1e-9));
      expect(board.phones[0].leftEdge, closeTo(0, 1e-9));
      expect(board.phones[1].leftEdge, closeTo(15.24 + 0.6, 1e-9));
      expect(board.phones.every((p) => p.topEdge.abs() < 1e-9), isTrue);
      expect(board.phones[1].placement, contains('right of phone 1'));
    });

    test('the bezel gap between them is real space', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      final board = compiler.compile(Layouts.row(lobby.phones), lobby);

      final seam = board.coverage.seamRects().single;
      expect(seam.width, closeTo(0.6, 1e-6));
      expect(seam.height, closeTo(6.858, 1e-9));

      // Inside the board, backed by no screen: physics runs there anyway.
      expect(board.coverage.isCovered(seam.centerX, board.board.centerY),
          isFalse);
      expect(board.board.contains(seam.centerX, board.board.centerY), isTrue);
    });

    test('Gaps.flush closes it, for a desktop test board', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      final board =
          compiler.compile(Layouts.row(lobby.phones, gap: Gaps.flush), lobby);

      expect(board.coverage.seamRects(), isEmpty);
      expect(board.board.width, closeTo(15.24 * 2, 1e-9));
    });
  });

  group('Layouts.column reproduces the old stack exactly', () {
    test('three phones, stacked, left edges flush', () {
      final lobby = lobbyOf([phone('p1'), phone('p2'), phone('p3')]);
      final board = compiler.compile(Layouts.column(lobby.phones), lobby);

      expect(board.board.width, closeTo(15.24, 1e-9));
      expect(board.board.height, closeTo(6.858 * 3 + 0.6 * 2, 1e-9));

      expect(board.phones[0].topEdge, closeTo(0, 1e-9));
      expect(board.phones[1].topEdge, closeTo(6.858 + 0.6, 1e-9));
      expect(board.phones[2].topEdge, closeTo((6.858 + 0.6) * 2, 1e-9));
      expect(board.phones.every((p) => p.leftEdge.abs() < 1e-9), isTrue);
      expect(board.phones[1].placement, contains('below phone 1'));
    });

    test('its seams are horizontal bands', () {
      final lobby = lobbyOf([phone('p1'), phone('p2'), phone('p3')]);
      final board = compiler.compile(Layouts.column(lobby.phones), lobby);

      final seams = board.coverage.seamRects();
      expect(seams, hasLength(2));
      for (final seam in seams) {
        expect(seam.width, closeTo(15.24, 1e-9));
        expect(seam.height, closeTo(0.6, 1e-6));
      }
    });
  });

  group('Layouts.grid packs two axes at once', () {
    test('fills row by row, so the first half is the top row', () {
      final phones = [for (var i = 1; i <= 6; i++) phone('p$i')];
      final plan = Layouts.grid(phones, rows: 2);
      final board = compiler.compile(plan, lobbyOf(phones));

      final tops = {for (final s in board.slices) s.phoneId: s.viewport};
      // p1..p3 are the top row, p4..p6 the bottom.
      for (final top in ['p1', 'p2', 'p3']) {
        for (final bottom in ['p4', 'p5', 'p6']) {
          expect(
            tops[top]!.bottom <= tops[bottom]!.top,
            isTrue,
            reason: '$top should sit above $bottom',
          );
        }
      }
    });

    test('columns widen the board and rows deepen it', () {
      final four = [for (var i = 1; i <= 4; i++) phone('p$i')];
      final two = [for (var i = 1; i <= 2; i++) phone('p$i')];
      final wide = compiler.compile(
        Layouts.grid(four, rows: 2),
        lobbyOf(four),
      );
      final narrow = compiler.compile(
        Layouts.grid(two, rows: 2),
        lobbyOf(two),
      );

      expect(wide.phones, hasLength(4));
      // 2x2 against 1x2: same depth, twice the columns.
      expect(wide.board.height, closeTo(narrow.board.height, 1e-9));
      expect(wide.board.width, greaterThan(narrow.board.width * 1.9));
    });

    test('refuses a count that will not fill the rows', () {
      final phones = [for (var i = 1; i <= 5; i++) phone('p$i')];
      expect(
        () => Layouts.grid(phones, rows: 2),
        throwsA(isA<BoardPlanError>()),
        reason: 'five phones cannot make two equal rows',
      );
      expect(
        () => Layouts.grid(phones, rows: 0),
        throwsA(isA<BoardPlanError>()),
      );
    });

    test('mismatched phones meet at the seam, not at their far edges', () {
      // A deep phone facing a shallow one. Seam-aligned, the shallow phone
      // gives up its far edge and both still touch across the middle.
      final phones = [
        phone('deep', heightMm: 160),
        phone('shallow', heightMm: 120),
      ];
      final board = compiler.compile(
        Layouts.grid(phones, rows: 2),
        lobbyOf(phones),
      );
      final deep = board.slices.firstWhere((s) => s.phoneId == 'deep').viewport;
      final shallow =
          board.slices.firstWhere((s) => s.phoneId == 'shallow').viewport;

      // Deep is the top row; its bottom edge and shallow's top edge are a
      // bezel apart, not a bezel plus the depth difference.
      final gapMm = (shallow.top - deep.bottom) / 0.1;
      expect(gapMm, closeTo(6, 0.5), reason: 'both bezels, and nothing else');
    });

    test('a narrow phone is packed against its neighbour, not left floating',
        () {
      // A block of four with one smaller phone in it. Laid into a column as
      // wide as the biggest screen, that phone floated centred in it with a gap
      // either side — the board still validated, because the gap was inside the
      // tolerance for two bezels, and then the round ran with a dead strip down
      // the middle of it.
      final phones = [
        phone('you'),
        phone('small', widthMm: 52, heightMm: 120),
        phone('p3'),
        phone('p4'),
      ];
      final board = compiler.compile(
        Layouts.grid(phones, rows: 2),
        lobbyOf(phones),
      );

      final you = board.slices.firstWhere((s) => s.phoneId == 'you').viewport;
      final small =
          board.slices.firstWhere((s) => s.phoneId == 'small').viewport;

      final gapMm = (small.left - you.right) / 0.1;
      expect(gapMm, closeTo(6, 0.5),
          reason: 'both bezels and nothing else — the small phone should be '
              'pushed left until it touches its neighbour');
    });

    test('no hole along a row, at any size or any count', () {
      // The guarantee that replaced columns. A phone is placed against the one
      // before it, so the only space anywhere along a row is the bezels between
      // two casings — whatever sizes turn up, and however many are playing.
      //
      // Sizes chosen to be awkward on purpose: a tiny phone between two large
      // ones is the case that used to leave a hole on both sides of itself, and
      // no amount of aligning within a column could have closed it.
      final sizes = <double>[52, 68.58, 80, 58, 75, 62, 84, 55];
      for (final count in [4, 6, 8]) {
        final phones = [
          for (var i = 0; i < count; i++)
            phone('p$i', widthMm: sizes[i], heightMm: 100 + sizes[i]),
        ];
        final board = compiler.compile(
          Layouts.grid(phones, rows: 2),
          lobbyOf(phones),
        );
        final columns = count ~/ 2;

        for (var r = 0; r < 2; r++) {
          for (var c = 0; c < columns - 1; c++) {
            final left = board.slices
                .firstWhere((s) => s.phoneId == 'p${r * columns + c}')
                .viewport;
            final right = board.slices
                .firstWhere((s) => s.phoneId == 'p${r * columns + c + 1}')
                .viewport;
            expect((right.left - left.right) / 0.1, closeTo(6, 0.5),
                reason: '$count phones, row $r: a hole between $c and ${c + 1}');
          }
        }
      }
    });

    test('the seam between two columns runs straight down the board', () {
      // Packing each row and then centring it staggered the grid: rows of
      // different total width drifted apart, so columns stopped standing over
      // each other. Rows are slid onto their shared seam instead.
      final phones = [
        phone('you', widthMm: 68.58, heightMm: 152.4),
        phone('r0c1', widthMm: 64, heightMm: 140),
        phone('r1c0', widthMm: 70, heightMm: 150),
        phone('r1c1', widthMm: 60, heightMm: 135),
      ];
      final board = compiler.compile(
        Layouts.grid(phones, rows: 2),
        lobbyOf(phones),
      );

      final topLeft = board.slices.firstWhere((s) => s.phoneId == 'you').viewport;
      final topRight =
          board.slices.firstWhere((s) => s.phoneId == 'r0c1').viewport;
      final bottomLeft =
          board.slices.firstWhere((s) => s.phoneId == 'r1c0').viewport;
      final bottomRight =
          board.slices.firstWhere((s) => s.phoneId == 'r1c1').viewport;

      expect(bottomLeft.right, closeTo(topLeft.right, 0.01),
          reason: 'the left column does not stand over itself');
      expect(bottomRight.left, closeTo(topRight.left, 0.01),
          reason: 'the right column does not stand over itself');
    });

    test('a phone joins its neighbours, not the one diagonally opposite', () {
      // The symptom of a staggered grid, and the one that shows on the
      // placement diagram: a phone in the top-left corner reporting a connector
      // to the phone in the bottom-right.
      final phones = [
        phone('you', widthMm: 80, heightMm: 170),
        phone('r0c1', widthMm: 45, heightMm: 95),
        phone('r1c0', widthMm: 52, heightMm: 110),
        phone('r1c1', widthMm: 78, heightMm: 165),
      ];
      final board = compiler.compile(
        Layouts.grid(phones, rows: 2),
        lobbyOf(phones),
      );

      final diagonals = board.links.where((l) =>
          (l.phoneId == 'you' && l.partnerId == 'r1c1') ||
          (l.phoneId == 'r0c1' && l.partnerId == 'r1c0'));
      expect(diagonals, isEmpty,
          reason: 'corners are joined across the middle of the board');
    });

    test('every phone still meets one across the seam', () {
      // What packing rows independently could have cost: rows no longer line up
      // column by column, so this is the thing worth checking rather than
      // assuming. Screens are joined by where they actually are, not by a grid
      // index, which is why it holds.
      final sizes = <double>[52, 68.58, 80, 58, 75, 62, 84, 55];
      for (final count in [4, 6, 8]) {
        final phones = [
          for (var i = 0; i < count; i++)
            phone('p$i', widthMm: sizes[i], heightMm: 100 + sizes[i]),
        ];
        final board = compiler.compile(
          Layouts.grid(phones, rows: 2),
          lobbyOf(phones),
        );
        final columns = count ~/ 2;

        for (final slice in board.slices) {
          final index = int.parse(slice.phoneId.substring(1));
          final myRow = index ~/ columns;

          final acrossTheSeam = board.links.where((l) {
            if (l.phoneId != slice.phoneId || l.partnerId == null) return false;
            final theirRow =
                int.parse(l.partnerId!.substring(1)) ~/ columns;
            return theirRow != myRow;
          });

          expect(acrossTheSeam, isNotEmpty,
              reason: '$count phones: ${slice.phoneId} faces nobody');
        }
      }
    });

    test('every neighbour in a mixed block is genuinely joined', () {
      // Whatever sizes turn up. Not measured in millimetres — the number that
      // matters is whether the platform calls them neighbours, because that is
      // what puts a stripe on the two edges and what the seam is built on.
      final phones = [
        phone('a'),
        phone('b', widthMm: 55, heightMm: 118),
        phone('c', widthMm: 80, heightMm: 170),
        phone('d', widthMm: 62, heightMm: 140),
        phone('e'),
        phone('f', widthMm: 75, heightMm: 160),
      ];
      final board = compiler.compile(
        Layouts.grid(phones, rows: 2),
        lobbyOf(phones),
      );

      bool joined(String x, String y) => board.links.any(
            (l) => l.phoneId == x && l.partnerId == y,
          );

      // Along each row, and across the seam between them.
      for (final pair in [
        ['a', 'b'],
        ['b', 'c'],
        ['d', 'e'],
        ['e', 'f'],
        ['a', 'd'],
        ['b', 'e'],
        ['c', 'f'],
      ]) {
        expect(joined(pair[0], pair[1]), isTrue,
            reason: '${pair[0]} and ${pair[1]} are not neighbours');
      }
    });

    test('a block of four leaves nothing but bezels between screens', () {
      // The whole point of pulling columns to the seam. Every gap on the board
      // should be two bezels and no more — before this, a smaller phone sat
      // 38mm from the one below it, a hair inside the 40mm at which the
      // platform stops calling two screens neighbours at all.
      final phones = [
        phone('you'),
        phone('small', widthMm: 52, heightMm: 120),
        phone('p3'),
        phone('p4'),
      ];
      final board = compiler.compile(
        Layouts.grid(phones, rows: 2),
        lobbyOf(phones),
      );

      for (final verdict in BoardLinks.explain(board.slices)) {
        if (!verdict.joined) continue;
        expect(verdict.gap / 0.1, closeTo(6, 0.5),
            reason: '${verdict.aId} and ${verdict.bId} are '
                '${(verdict.gap / 0.1).round()}mm apart');
      }
    });

    test('a single row is just a row', () {
      final phones = [for (var i = 1; i <= 3; i++) phone('p$i')];
      final board = compiler.compile(
        Layouts.grid(phones, rows: 1),
        lobbyOf(phones),
      );
      expect(board.board.width, greaterThan(board.board.height));
    });

    test('the playfield is what every facing pair can see', () {
      // A narrow phone opposite a wide one: the column is only as wide as the
      // narrow one, because the wide phone's overhang has no screen under it.
      final phones = [phone('wide', widthMm: 80), phone('narrow', widthMm: 60)];
      final board = compiler.compile(
        Layouts.grid(phones, rows: 2),
        lobbyOf(phones),
      );
      expect(board.board.width / 0.1, closeTo(60, 0.5));
    });
  });

  group('a screen is one size, not two', () {
    // The only fixtures in the suite that describe an impossible device, and
    // deliberately so: here the impossible device *is* the subject. Everywhere
    // else a fixture derives its pixels from its millimetres, because a test
    // built on non-square pixels proves nothing about a real table.
    //
    // The compiler reserves a slot of widthMm by heightMm, but hands back a
    // screen sized from the pixel count and the density — and the density is
    // worked out from the width alone. Let those drift and a phone is drawn to
    // one size while given room for another: it reaches over its neighbour on
    // the glass and on the diagram, while the plan validates cleanly, because
    // overlap was only ever checked against the slot.
    test('millimetres that contradict the pixels are refused', () {
      final honest = phone('ok');
      final lying = PhoneSpec(
        phoneId: 'lying',
        label: 'lying',
        // A ruler-corrected width with the estimated height left behind: the
        // exact thing the metrics card invites.
        widthMm: 68.58,
        heightMm: 120,
        bezelMm: 3,
        dpi: 400,
        devicePixelRatio: 3,
        activePxWidth: 1080,
        activePxHeight: 2400,
      );

      expect(
        () => compiler.compile(
          Layouts.row([honest, lying]),
          lobbyOf([honest, lying]),
        ),
        throwsA(isA<BoardPlanError>()),
      );
    });

    test('the error names the phone and the size its pixels imply', () {
      final lying = PhoneSpec(
        phoneId: 'p9',
        label: 'p9',
        widthMm: 68.58,
        heightMm: 120,
        bezelMm: 3,
        dpi: 400,
        devicePixelRatio: 3,
        activePxWidth: 1080,
        activePxHeight: 2400,
      );

      expect(
        () => compiler.compile(Layouts.row([lying]), lobbyOf([lying])),
        throwsA(
          isA<BoardPlanError>().having((e) => e.message, 'message',
              allOf(contains('p9'), contains('152.4'))),
        ),
      );
    });

    test('correcting the width carries the height with it', () {
      // Pixels are square, so one measured edge fixes the other. This is what
      // stops the metrics card from being able to create the board above.
      const metrics = DeviceMetrics(
        activePxWidth: 1080,
        activePxHeight: 2400,
        widthMm: 60,
        heightMm: 133.3,
        bezelMm: 3,
        devicePixelRatio: 3,
      );

      // Somebody measures the short edge properly and types it in.
      final corrected = metrics.copyWith(widthMm: 68.58);
      final spec = PhoneSpec.fromMetrics('p1', corrected);

      expect(spec.widthMm, closeTo(68.58, 0.01));
      expect(spec.heightMm, closeTo(68.58 * 2400 / 1080, 0.01),
          reason: 'the long edge should have followed the short one');

      // And the board it produces is sound.
      expect(
        () => compiler.compile(Layouts.row([spec]), lobbyOf([spec])),
        returnsNormally,
      );
    });

    test('what the compiler hands back is the size it reserved', () {
      final phones = [for (var i = 1; i <= 3; i++) phone('p$i')];
      final board = compiler.compile(
        Layouts.row(phones),
        lobbyOf(phones),
      );

      for (final slice in board.slices) {
        final spec = phones.firstWhere((p) => p.phoneId == slice.phoneId);
        // Laid sideways by `row`, so the screen's own long edge runs across.
        expect(slice.screen.height / 0.1, closeTo(spec.heightMm, 0.05));
        expect(slice.screen.width / 0.1, closeTo(spec.widthMm, 0.05));
      }
    });
  });

  group('the game decides the order', () {
    test('smallest first puts the little phone at the start', () {
      final small = phone('small', widthMm: 50, heightMm: 100);
      final big = phone('big', widthMm: 90, heightMm: 200);
      final lobby = lobbyOf([big, small]); // joined in the wrong order

      final board = compiler.compile(
        Layouts.row(lobby.phones, sort: PhoneSort.smallestFirst),
        lobby,
      );

      expect(board.phones.first.phoneId, 'small');
      expect(board.phones.last.phoneId, 'big');
    });

    test('largest last is how the ball bin wants its well', () {
      final small = phone('small', widthMm: 50, heightMm: 100);
      final big = phone('big', widthMm: 90, heightMm: 200);
      final lobby = lobbyOf([big, small]);

      final board = compiler.compile(
        Layouts.column(lobby.phones, sort: PhoneSort.largestLast),
        lobby,
      );

      expect(board.phones.first.phoneId, 'small');
      expect(board.phones.last.phoneId, 'big');
      expect(board.phones.last.topEdge, greaterThan(0));
    });

    test('a custom comparator works too', () {
      final lobby = lobbyOf([phone('b'), phone('a'), phone('c')]);
      final board = compiler.compile(
        Layouts.row(
          lobby.phones,
          sort: PhoneSort.by((x, y) => x.phoneId.compareTo(y.phoneId)),
        ),
        lobby,
      );
      expect(board.phones.map((p) => p.phoneId), ['a', 'b', 'c']);
    });

    test('a mixed board is only as wide as its smallest screen', () {
      final lobby = lobbyOf([
        phone('p1', widthMm: 60),
        phone('p2', widthMm: 80),
      ]);
      final board = compiler.compile(Layouts.row(lobby.phones), lobby);

      // Anything else would leave a dead zone that is not a real gap.
      expect(board.board.height, closeTo(6.0, 1e-9));
    });
  });

  group('freeform plans', () {
    test('a 2x2 grid compiles, with seams on both axes', () {
      final lobby = lobbyOf([
        phone('a'),
        phone('b'),
        phone('c'),
        phone('d'),
      ]);
      const dx = 68.58 + 6;
      const dy = 152.4 + 6;

      final board = compiler.compile(
        const BoardPlan([
          PhonePlacement('a', xMm: 0, yMm: 0),
          PhonePlacement('b', xMm: dx, yMm: 0),
          PhonePlacement('c', xMm: 0, yMm: dy),
          PhonePlacement('d', xMm: dx, yMm: dy),
        ], instruction: 'Two by two.'),
        lobby,
      );

      expect(board.board.width, closeTo((dx + 68.58) * 0.1, 1e-9));
      expect(board.board.height, closeTo((dy + 152.4) * 0.1, 1e-9));

      // Two vertical seams and two horizontal ones — a shape no enum could
      // have described.
      final seams = board.coverage.seamRects();
      expect(seams, hasLength(4));
      expect(seams.where((s) => s.width < s.height), hasLength(2));
      expect(seams.where((s) => s.height < s.width), hasLength(2));
    });

    test('the plan is normalised so the board starts at the origin', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      final board = compiler.compile(
        const BoardPlan([
          // Deliberately off in negative space.
          PhonePlacement('p1', xMm: -500, yMm: -200, turnDeg: 90),
          PhonePlacement('p2', xMm: -500 + 158.4, yMm: -200, turnDeg: 90),
        ]),
        lobby,
      );

      expect(board.board.left, 0);
      expect(board.board.top, 0);
      expect(board.phones.first.leftEdge, closeTo(0, 1e-9));
    });

    test('a helper result can be adjusted by hand', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      // Nudge the second phone a centimetre further out than the helper put it.
      // Centre, not corner: 10mm further out than the helper put it.
      final plan = Layouts.row(lobby.phones).withPlacement(
        const PhonePlacement('p2',
            xMm: 244.6, yMm: 34.29, turnDeg: 90, hint: 'a bit further'),
      );
      final board = compiler.compile(plan, lobby);

      expect(board.phones.last.leftEdge, closeTo(16.84, 1e-9));
      expect(board.phones.last.placement, 'a bit further');
      // The wider gap is a wider seam, and nothing else changes.
      expect(board.coverage.seamRects().single.width, closeTo(1.6, 1e-6));
    });

    test('a phone nudged out of reach is still rejected', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      final plan = Layouts.row(lobby.phones).withPlacement(
        const PhonePlacement('p2', xMm: 400, yMm: 0),
      );
      expect(
        () => compiler.compile(plan, lobby),
        throwsA(isA<BoardPlanError>()),
        reason: 'no bezel gap is 25cm wide — that is a plan bug',
      );
    });
  });

  group('turning a phone within the board', () {
    test('a sideways phone covers the board the other way round', () {
      final lobby = lobbyOf([phone('p1')]);

      final upright = compiler.compile(
        Layouts.row(lobby.phones, orientation: PhoneOrientation.upright),
        lobby,
      );
      final sideways = compiler.compile(
        Layouts.row(lobby.phones, orientation: PhoneOrientation.sideways),
        lobby,
      );

      // Same panel, footprint swapped.
      expect(upright.board.width, closeTo(6.858, 1e-9));
      expect(upright.board.height, closeTo(15.24, 1e-9));
      expect(sideways.board.width, closeTo(15.24, 1e-9));
      expect(sideways.board.height, closeTo(6.858, 1e-9));
    });

    test('the panel is never swapped — the turn carries the rotation', () {
      final lobby = lobbyOf([phone('p1')]);
      final sideways = compiler.compile(Layouts.row(lobby.phones), lobby);
      final me = sideways.phones.single;

      expect(me.turnRadians, closeTo(math.pi / 2, 1e-9));
      // Pixels stay in the phone's own portrait frame. There is exactly one
      // place rotation is handled, and it is the transform.
      expect(me.activePxWidth, closeTo(68.58 * 400 / 25.4, 1e-6));
      expect(me.activePxHeight, closeTo(152.4 * 400 / 25.4, 1e-6));

      // The board footprint is turned, and one world unit is still one
      // centimetre of real glass.
      expect(me.viewport.width, closeTo(15.24, 1e-9));
      expect(me.viewport.height, closeTo(6.858, 1e-9));
    });

    test('a turn is carried as an angle, not a quarter-turn count', () {
      final lobby = lobbyOf([phone('p1')]);
      final sideways = compiler.compile(Layouts.row(lobby.phones), lobby);
      final upright = compiler.compile(
        Layouts.row(lobby.phones, orientation: PhoneOrientation.upright),
        lobby,
      );

      // Turned one step clockwise on the table, so the surface turns one step
      // back — otherwise everything would read on its side.
      expect(sideways.phones.single.turnRadians, closeTo(math.pi / 2, 1e-9));
      

      // Nothing to cancel when the phone is left upright.
      expect(upright.phones.single.turnRadians, 0);
      
    });

    test('the transforms stay exact inverses when turned', () {
      // The property the seam depends on. It survives rotation because the
      // rotation is absorbed into the pixel dimensions rather than added as a
      // term here.
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      for (final orientation in PhoneOrientation.values) {
        final board = compiler.compile(
          Layouts.row(lobby.phones, orientation: orientation),
          lobby,
        );
        for (final p in board.phones) {
          for (final px in const [0.0, 137.0, 900.0]) {
            final world = p.physicalPxToWorld(px, px / 2);
            final back = p.worldToPhysicalPx(world.x, world.y);
            expect(back.x, closeTo(px, 1e-9), reason: '$orientation');
            expect(back.y, closeTo(px / 2, 1e-9), reason: '$orientation');
          }
        }
      }
    });

    test('it survives the wire, so each phone knows how to turn itself', () {
      final lobby = lobbyOf([phone('p1')]);
      final board = compiler.compile(Layouts.row(lobby.phones), lobby);
      final round = PhoneLayout.fromJson(board.phones.single.toJson());

      expect(round.turnRadians, closeTo(math.pi / 2, 1e-9));
      expect(round.activePxWidth, closeTo(68.58 * 400 / 25.4, 1e-6));
    });

    test('a board may mix orientations', () {
      // A row of sideways phones with one left upright beside them — the shape
      // that argues for per-phone turns rather than one setting for the board.
      final lobby = lobbyOf([phone('a'), phone('b')]);
      final board = compiler.compile(
        const BoardPlan([
          PhonePlacement('a', xMm: 0, yMm: 0, turnDeg: 90),
          PhonePlacement('b', xMm: 116.49, yMm: 0),
        ]),
        lobby,
      );

      final a = board.forPhone('a')!;
      final b = board.forPhone('b')!;
      expect(a.viewport.width, closeTo(15.24, 1e-9));
      expect(a.viewport.height, closeTo(6.858, 1e-9));
      expect(b.viewport.width, closeTo(6.858, 1e-9));
      expect(b.viewport.height, closeTo(15.24, 1e-9));
      expect(a.turnRadians, closeTo(math.pi / 2, 1e-9));
      expect(b.turnRadians, 0);
    });

    test('the instruction says which way up, not just which way along', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);

      final sideways = Layouts.row(lobby.phones).instruction!;
      final upright = Layouts.row(
        lobby.phones,
        orientation: PhoneOrientation.upright,
      ).instruction!;

      expect(sideways, contains('on their sides'));
      expect(sideways, contains('short edges touching'));
      expect(upright, contains('upright'));
      expect(upright, contains('long edges touching'));
    });
  });

  group('the compiled slices are what the placement diagram draws', () {
    test('they follow the board, not the order phones joined in', () {
      // The bug this guards: the diagram used to be built from the lobby's
      // join order, so it showed the wrong arrangement the moment a game
      // sorted its phones — and both shipped games do.
      final small = phone('small', widthMm: 50, heightMm: 100);
      final big = phone('big', widthMm: 90, heightMm: 200);
      final lobby = lobbyOf([big, small]); // joined big-first

      final board = compiler.compile(
        Layouts.row(lobby.phones, sort: PhoneSort.smallestFirst),
        lobby,
      );

      expect(board.slices.map((s) => s.phoneId), ['small', 'big']);
      expect(board.slices.first.viewport.left,
          lessThan(board.slices.last.viewport.left));
    });

    test('each slice is that screen exactly, gaps and all', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      final board = compiler.compile(Layouts.row(lobby.phones), lobby);

      for (final slice in board.slices) {
        final layout = board.forPhone(slice.phoneId)!;
        expect(slice.viewport.left, closeTo(layout.viewport.left, 1e-9));
        expect(slice.viewport.width, closeTo(layout.viewport.width, 1e-9));
        expect(slice.viewport.height, closeTo(layout.viewport.height, 1e-9));
      }

      // The real bezel gap is visible between them, not a fixed spacer.
      final gap = board.slices[1].viewport.left - board.slices[0].viewport.right;
      expect(gap, closeTo(0.6, 1e-6));
    });

    test('they carry labels, and survive the wire', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      final board = compiler.compile(Layouts.column(lobby.phones), lobby);

      expect(board.slices.first.label, 'phone p1');

      final round = PhoneSlice.fromJson(board.slices.first.toJson());
      expect(round.phoneId, board.slices.first.phoneId);
      expect(round.label, board.slices.first.label);
      expect(round.viewport.top, closeTo(board.slices.first.viewport.top, 1e-9));
    });

    test('a stack really is stacked, so the picture cannot be a row', () {
      final lobby = lobbyOf([phone('p1'), phone('p2'), phone('p3')]);
      final board = compiler.compile(Layouts.column(lobby.phones), lobby);

      // Every screen shares a left edge and descends — no proportions guess
      // needed to know this is a column.
      expect(board.slices.every((s) => s.viewport.left.abs() < 1e-9), isTrue);
      for (var i = 1; i < board.slices.length; i++) {
        expect(board.slices[i].viewport.top,
            greaterThan(board.slices[i - 1].viewport.top));
      }
    });

    test('a grid keeps its two dimensions', () {
      final lobby = lobbyOf([phone('a'), phone('b'), phone('c'), phone('d')]);
      const dx = 68.58 + 6;
      const dy = 152.4 + 6;
      final board = compiler.compile(
        const BoardPlan([
          PhonePlacement('a', xMm: 0, yMm: 0),
          PhonePlacement('b', xMm: dx, yMm: 0),
          PhonePlacement('c', xMm: 0, yMm: dy),
          PhonePlacement('d', xMm: dx, yMm: dy),
        ]),
        lobby,
      );

      // Two distinct rows and two distinct columns — a shape the old
      // row-or-column diagram could not have drawn at all.
      final lefts = board.slices.map((s) => s.viewport.left).toSet();
      final tops = board.slices.map((s) => s.viewport.top).toSet();
      expect(lefts, hasLength(2));
      expect(tops, hasLength(2));
    });
  });

  group('a bad plan is refused before anyone is told to move', () {
    final lobby = lobbyOf([phone('p1'), phone('p2')]);

    test('overlapping screens', () {
      expect(
        () => compiler.compile(
          const BoardPlan([
            PhonePlacement('p1', xMm: 0, yMm: 0),
            PhonePlacement('p2', xMm: 10, yMm: 0), // sits on top of p1
          ]),
          lobby,
        ),
        throwsA(isA<BoardPlanError>().having(
          (e) => e.message, 'message', contains('overlap'))),
      );
    });

    test('a phone left unplaced', () {
      expect(
        () => compiler.compile(
          const BoardPlan([PhonePlacement('p1', xMm: 0, yMm: 0)]),
          lobby,
        ),
        throwsA(isA<BoardPlanError>().having(
          (e) => e.message, 'message', contains('unplaced'))),
      );
    });

    test('an unknown phone', () {
      expect(
        () => compiler.compile(
          const BoardPlan([
            PhonePlacement('p1', xMm: 0, yMm: 0),
            PhonePlacement('p2', xMm: 158.4, yMm: 0),
            PhonePlacement('ghost', xMm: 400, yMm: 0),
          ]),
          lobby,
        ),
        throwsA(isA<BoardPlanError>().having(
          (e) => e.message, 'message', contains('unknown'))),
      );
    });

    test('the same phone twice', () {
      expect(
        () => compiler.compile(
          const BoardPlan([
            PhonePlacement('p1', xMm: 0, yMm: 0),
            PhonePlacement('p1', xMm: 158.4, yMm: 0),
          ]),
          lobby,
        ),
        throwsA(isA<BoardPlanError>().having(
          (e) => e.message, 'message', contains('more than once'))),
      );
    });

    test('a phone marooned across the room', () {
      expect(
        () => compiler.compile(
          const BoardPlan([
            PhonePlacement('p1', xMm: 0, yMm: 0),
            PhonePlacement('p2', xMm: 2000, yMm: 0),
          ]),
          lobby,
        ),
        throwsA(isA<BoardPlanError>().having(
          (e) => e.message, 'message', contains('disconnected'))),
      );
    });

    test('a non-finite position', () {
      expect(
        () => compiler.compile(
          const BoardPlan([
            PhonePlacement('p1', xMm: 0, yMm: 0),
            PhonePlacement('p2', xMm: double.nan, yMm: 0),
          ]),
          lobby,
        ),
        throwsA(isA<BoardPlanError>()),
      );
    });
  });

  group('one phone alone', () {
    test('is a whole board', () {
      final lobby = lobbyOf([phone('p1')]);
      final board = compiler.compile(Layouts.row(lobby.phones), lobby);

      expect(board.board.width, closeTo(15.24, 1e-9));
      expect(board.coverage.seamRects(), isEmpty);
      expect(board.phones.single.placement, contains('alone'));
    });
  });

  group('the transforms survive compilation', () {
    test('touch and render transforms are exact inverses', () {
      // If these ever drift apart, a finger and the thing it grabs stop
      // agreeing — and so do two phones about where the bird is.
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      final board = compiler.compile(Layouts.row(lobby.phones), lobby);

      for (final p in board.phones) {
        for (final px in const [0.0, 137.0, 1200.0, 2400.0]) {
          final world = p.physicalPxToWorld(px, px / 2);
          final back = p.worldToPhysicalPx(world.x, world.y);
          expect(back.x, closeTo(px, 1e-9));
          expect(back.y, closeTo(px / 2, 1e-9));
        }
      }
    });

    test('6mm of bezel sits between the two lit areas', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      final board = compiler.compile(Layouts.row(lobby.phones), lobby);

      final gap =
          board.phones[1].viewport.left - board.phones[0].viewport.right;
      expect(gap, closeTo(0.6, 1e-6));
    });

    test('a viewport covers exactly its own screen', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      final board = compiler.compile(Layouts.row(lobby.phones), lobby);
      final v = board.phones[1].viewport;

      expect(v.left, closeTo(15.84, 1e-9));
      expect(v.width, closeTo(15.24, 1e-9));
      expect(v.height, closeTo(6.858, 1e-9));
    });

    test('join order is honoured when the game asks for it', () {
      final lobby = lobbyOf([
        phone('a', widthMm: 60, heightMm: 100),
        phone('b', widthMm: 60, heightMm: 140),
        phone('c', widthMm: 60, heightMm: 120),
      ]);
      final board = compiler.compile(
        Layouts.row(lobby.phones, sort: PhoneSort.joinOrder),
        lobby,
      );

      expect(board.phones.map((p) => p.phoneId), ['a', 'b', 'c']);
      expect(board.phones[0].leftEdge, closeTo(0, 1e-9));
      expect(board.phones[1].leftEdge, closeTo(10.0 + 0.6, 1e-9));
      expect(board.phones[2].leftEdge, closeTo(10.6 + 14.0 + 0.6, 1e-9));
      expect(board.phones[2].index, 2);
    });

    test('a touch maps back to the world point it came from', () {
      final lobby = lobbyOf([phone('p1'), phone('p2')]);
      final board = compiler.compile(Layouts.row(lobby.phones), lobby);
      final second = board.phones[1];

      // A touch in the middle of the second screen.
      final world = second.physicalPxToWorld(
        second.activePxWidth / 2,
        second.activePxHeight / 2,
      );
      final back = second.worldToPhysicalPx(world.x, world.y);

      expect(back.x, closeTo(second.activePxWidth / 2, 1e-6));
      expect(back.y, closeTo(second.activePxHeight / 2, 1e-6));

      // And it really is on the far side of the seam.
      expect(world.x, greaterThan(15.24));
    });

    test('every phone renders the same world at the same physical scale', () {
      final lobby = lobbyOf([
        phone('p1'),
        // Same physical size, twice the pixels: a denser screen.
        PhoneSpec(
          phoneId: 'p2',
          label: 'dense',
          widthMm: 68.58,
          heightMm: 152.4,
          bezelMm: 3,
          dpi: 800,
          devicePixelRatio: 4,
          activePxWidth: 68.58 * 800 / 25.4,
          activePxHeight: 152.4 * 800 / 25.4,
        ),
      ]);
      final board = compiler.compile(Layouts.row(lobby.phones), lobby);

      // Different densities, identical world footprint.
      expect(
        board.phones[0].viewport.width,
        closeTo(board.phones[1].viewport.width, 1e-9),
      );
    });
  });
}

/// Left/top edge of a compiled screen, which is what these expectations were
/// originally written against. The layout itself is centre-based now, because a
/// screen that can be turned has no meaningful axis-aligned corner.
extension EdgeReadout on PhoneLayout {
  double get leftEdge => viewport.left;
  double get topEdge => viewport.top;
}
