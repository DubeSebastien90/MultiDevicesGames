import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/ball_bin/ball_bin_game.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_audit.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_compiler.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_links.dart';
import 'package:multiscreen_slingshot/sdk/layout/board_plan.dart';
import 'package:multiscreen_slingshot/sdk/layout/phone_spec.dart';

/// The audit exists to explain a real table, so these tests check it explains
/// the *failures* — a dump that only describes success is no use.
PhoneSpec dev(String id, {double bezelMm = 3}) => PhoneSpec(
  phoneId: id,
  label: id,
  widthMm: 68.58,
  heightMm: 152.4,
  bezelMm: bezelMm,
  dpi: 400,
  devicePixelRatio: 3,
  activePxWidth: 1080,
  activePxHeight: 2400,
);

Map<String, dynamic> auditOf(List<PhoneSpec> phones) {
  final lobby = LobbyInfo(phones);
  final plan = const BallBinGame().planBoard(lobby);
  final board = const BoardCompiler().compile(plan, lobby);
  return BoardAudit.of(
    gameId: 'ballbin',
    lobby: lobby,
    plan: plan,
    board: board,
  );
}

void main() {
  group('every pair is accounted for, joined or not', () {
    test('a four-phone stack explains all six pairs', () {
      final audit = auditOf([dev('p1'), dev('p2'), dev('p3'), dev('p4')]);
      final pairs = audit['pairs'] as List;

      // 4 choose 2.
      expect(pairs, hasLength(6));

      final joined = pairs.where((p) => (p as Map)['joined'] == true);
      expect(joined, hasLength(3), reason: 'a chain of four has three joins');

      // And the three non-joins say why, in words.
      for (final p in pairs.cast<Map<String, dynamic>>()) {
        expect(p['reason'], isNotEmpty);
        if (p['joined'] == false) {
          expect(p['reason'], isNot('joined'));
        }
      }
    });

    test('a rejected pair names the gap and the limit', () {
      final audit = auditOf([dev('p1'), dev('p2'), dev('p3')]);
      final rejected = (audit['pairs'] as List)
          .cast<Map<String, dynamic>>()
          .where((p) => p['joined'] == false)
          .toList();

      expect(rejected, isNotEmpty);
      final far = rejected.firstWhere((p) => p['axis'] == 'stacked');
      expect(far['reason'], contains('gap '));
      expect(far['reason'], contains('exceeds'));
      expect(far['gap'], greaterThan(BoardLinks.maxJoinGap));
    });
  });

  group('the summary is the headline', () {
    test('a healthy board says so plainly', () {
      final audit = auditOf([dev('p1'), dev('p2'), dev('p3')]);
      expect(audit['summary'], contains('2 join(s)'));
      expect(audit['summary'], contains('Nothing rejected on gap'));
    });

    test('chunky bezels still join — the two thresholds agree now', () {
      // 20mm each is a 40mm gap, exactly the limit. This used to fall in the
      // window between the join threshold (30mm) and the connectivity check
      // (40mm): the board validated, no pair joined, and every phone fell back
      // to an inward stripe — one colour for the whole table, silently. That
      // window is gone.
      final audit = auditOf([
        dev('p1', bezelMm: 20),
        dev('p2', bezelMm: 20),
        dev('p3', bezelMm: 20),
      ]);

      expect(audit['summary'], contains('2 join(s)'));
      final links = (audit['links'] as List).cast<Map<String, dynamic>>();
      expect(links.any((l) => l['with'] == '(inward)'), isFalse,
          reason: 'nothing should fall back to an inward stripe in a stack');
      expect(links.map((l) => l['color']).toSet(), {0, 1});
    });

    test('a gap too wide to be a bezel is a loud error, not a quiet miscolour',
        () {
      // Past the shared threshold the plan is refused outright, so the round
      // never starts and the host is told why — rather than everyone placing
      // phones against connectors that all look the same.
      expect(
        () => auditOf([dev('p1'), dev('p2', bezelMm: 60), dev('p3')]),
        throwsA(isA<BoardPlanError>()),
      );
    });
  });

  group('what the dump contains', () {
    test('the measurements a human typed, bezel first', () {
      final audit = auditOf([dev('p1', bezelMm: 7), dev('p2')]);
      final phones = (audit['phones'] as List).cast<Map<String, dynamic>>();

      expect(phones.first.keys.toList()[2], 'bezelMm',
          reason: 'the field most likely to break a join should be prominent');
      expect(phones.first['bezelMm'], 7);
      expect(phones.first['widthMm'], 68.58);
    });

    test('the plan the game asked for, and what it compiled to', () {
      final audit = auditOf([dev('p1'), dev('p2'), dev('p3')]);

      final plan = audit['plan'] as Map<String, dynamic>;
      expect(plan['instruction'], contains('Stack'));
      expect(plan['allowGaps'], isFalse);
      expect((plan['placements'] as List), hasLength(3));

      final board = audit['board'] as Map<String, dynamic>;
      expect((board['screens'] as List), hasLength(3));
      expect(board['heightWorld'], greaterThan(board['widthWorld']));
    });

    test('it round-trips as JSON, so it can be pasted anywhere', () {
      final text = BoardAudit.toPrettyJson(auditOf([dev('p1'), dev('p2')]));
      expect(text, contains('"pairs"'));
      expect(text, contains('"summary"'));
      expect(text, contains('maxJoinGapWorld'));
      // Pretty-printed, because a human reads it.
      expect(text, contains('\n  '));
    });
  });

  test('markers are derived from the verdicts, not computed twice', () {
    // The refactor that made the audit possible: one decision path. If these
    // ever disagree, a stripe exists that no verdict explains.
    final lobby = LobbyInfo([dev('p1'), dev('p2'), dev('p3')]);
    final board = const BoardCompiler()
        .compile(const BallBinGame().planBoard(lobby), lobby);

    final joinedPairs =
        BoardLinks.explain(board.slices).where((v) => v.joined).length;
    final joinMarkers = board.links.where((l) => l.isJoin).length;

    expect(joinMarkers, joinedPairs * 2);
  });
}
