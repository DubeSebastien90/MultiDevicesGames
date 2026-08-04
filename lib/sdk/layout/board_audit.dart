import 'dart:convert';
import 'dart:math' as math;

import 'board_compiler.dart';
import 'board_links.dart';
import 'board_plan.dart';
import 'phone_spec.dart';

/// A complete record of one board being laid out: what the phones reported, what
/// the game asked for, what came out, and **why each pair of screens was or was
/// not joined**.
///
/// This exists because a photograph of four phones cannot answer "why is that
/// stripe missing". Synthetic tests pass with made-up devices; real tables have
/// real measurements, and the interesting failures live in the numbers a human
/// typed into the metrics card. So the host dumps this on every round and the
/// numbers can be read directly instead of inferred from colours.
class BoardAudit {
  const BoardAudit._();

  static Map<String, dynamic> of({
    required String gameId,
    required LobbyInfo lobby,
    required BoardPlan plan,
    required BoardLayout board,
  }) {
    final verdicts = BoardLinks.explain(board.slices);

    return {
      'game': gameId,
      'when': DateTime.now().toIso8601String(),
      'maxJoinGapWorld': BoardLinks.maxJoinGap,

      // What each phone said about itself. The bezel is the field most likely
      // to break joins, so it is first.
      'phones': [
        for (final p in lobby.phones)
          {
            'id': p.phoneId,
            'label': p.label,
            'bezelMm': p.bezelMm,
            'widthMm': p.widthMm,
            'heightMm': p.heightMm,
            'dpi': double.parse(p.dpi.toStringAsFixed(1)),
            'dpr': p.devicePixelRatio,
            'px': '${p.activePxWidth.round()}x${p.activePxHeight.round()}',
          },
      ],

      // What the game asked for.
      'plan': {
        'instruction': plan.instruction,
        'allowGaps': plan.allowGaps,
        'placements': [
          for (final pl in plan.placements)
            {
              'id': pl.phoneId,
              'xMm': double.parse(pl.xMm.toStringAsFixed(2)),
              'yMm': double.parse(pl.yMm.toStringAsFixed(2)),
              'turnDeg': double.parse(pl.turnDeg.toStringAsFixed(2)),
            },
        ],
      },

      // What it compiled to, in world units.
      'board': {
        'widthWorld': double.parse(board.board.width.toStringAsFixed(3)),
        'heightWorld': double.parse(board.board.height.toStringAsFixed(3)),
        'screens': [
          for (final s in board.slices)
            {
              'id': s.phoneId,
              'left': double.parse(s.viewport.left.toStringAsFixed(3)),
              'top': double.parse(s.viewport.top.toStringAsFixed(3)),
              'right': double.parse(s.viewport.right.toStringAsFixed(3)),
              'bottom': double.parse(s.viewport.bottom.toStringAsFixed(3)),
              'turnDeg': double.parse(
                (s.screen.turnRadians * 180 / 3.141592653589793)
                    .toStringAsFixed(2),
              ),
            },
        ],
      },

      // The whole point: every pair, with the reason.
      'pairs': [for (final v in verdicts) v.toJson()],

      'links': [
        for (final l in board.links)
          {
            'phone': l.phoneId,
            'with': l.partnerId ?? '(inward)',
            'color': l.colorIndex,
          },
      ],

      // The one-line answer, for when the rest is too much to read.
      'summary': _summarise(verdicts, board),
    };
  }

  static String _summarise(List<LinkVerdict> verdicts, BoardLayout board) {
    final joins = verdicts.where((v) => v.joined).length;
    final inward = board.links.where((l) => !l.isJoin).length;

    // Not every gap rejection is a problem. In a chain of four, the first and
    // last phones are rejected on gap and *should* be — there are two phones
    // between them. What is suspicious is a gap too small for anything to be
    // in between: those two really are neighbours, and something about the
    // measurements pushed them apart.
    final narrowest = board.slices
        .map((s) => math.min(s.screen.width, s.screen.height))
        .fold<double>(double.infinity, math.min);
    final suspicious = verdicts
        .where((v) =>
            !v.joined &&
            v.reason.startsWith('gap ') &&
            v.gap.isFinite &&
            v.gap < narrowest)
        .length;

    if (inward > 0 && joins == 0) {
      return 'NO joins found — every phone fell back to an inward stripe, so '
          'they will all be the same colour. '
          '${suspicious > 0 ? "$suspicious pair(s) were rejected on gap "
              "size: check bezelMm." : "No pair shared an edge at all."}';
    }
    if (suspicious > 0) {
      return '$joins join(s) found, but $suspicious pair(s) were rejected '
          'on gap size — check bezelMm, and see "pairs" below.';
    }
    return '$joins join(s), $inward inward stripe(s). Nothing rejected on gap.';
  }

  static String toPrettyJson(Map<String, dynamic> audit) =>
      const JsonEncoder.withIndent('  ').convert(audit);
}
