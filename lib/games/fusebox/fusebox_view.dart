import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import 'fusebox_config.dart';

/// Fuse Box's pixels: a grid of lights, on or off, on the host's own
/// schedule.
///
/// Whether a light is lit rides in `frame.sharedState['lit']`, keyed by
/// entity id, rather than in the entity's own props: a cell's position and
/// size are the only things about it that are fixed for the round, and
/// lit/unlit is exactly the kind of small, slow-changing fact `sharedState`
/// exists for.
class FuseBoxView extends GameView {
  FuseBoxView(this.context);

  final ViewContext context;

  final _fill = Paint()..isAntiAlias = true;
  final _stroke = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke;

  @override
  void render(Canvas canvas, Frame frame) {
    final view = frame.visible;
    final board = frame.board;

    _fill.color = const Color(FuseBoxConfig.colorBackground);
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _fill,
    );
    _fill.color = const Color(FuseBoxConfig.colorPlayfield);
    canvas.drawRect(
      Rect.fromLTWH(board.left, board.top, board.width, board.height),
      _fill,
    );

    final lit = _litMap(frame);
    for (final e in frame.ofKind('cell')) {
      _drawCell(canvas, e, lit[e.id] ?? false);
    }
  }

  Map<String, bool> _litMap(Frame frame) {
    final raw = frame.sharedState['lit'];
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries) '${entry.key}': entry.value == true,
    };
  }

  void _drawCell(Canvas canvas, RenderEntity e, bool lit) {
    final size = e.propDouble('size');
    final rect = Rect.fromCenter(center: Offset(e.x, e.y), width: size, height: size);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(size * 0.16));

    if (lit) {
      // A soft glow behind the tile, so a lit cell reads as *lit* rather than
      // merely a different shade, at arm's length across a table.
      _fill.color = const Color(FuseBoxConfig.colorCellOn).withValues(alpha: 0.28);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.inflate(size * 0.16),
          Radius.circular(size * 0.2),
        ),
        _fill,
      );
    }

    _fill.color = Color(
      lit ? FuseBoxConfig.colorCellOn : FuseBoxConfig.colorCellOff,
    );
    canvas.drawRRect(rrect, _fill);

    _stroke
      ..color = const Color(FuseBoxConfig.colorCellRim)
      ..strokeWidth = size * 0.05;
    canvas.drawRRect(rrect, _stroke);
  }

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final secondsLeft = frame.sharedState['secondsLeft'];
    final taps = frame.sharedState['taps'];

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (secondsLeft is int) _pill(
            '${secondsLeft}s',
            color: secondsLeft <= 10
                ? const Color(0xFFFF6B6B)
                : const Color(0xFFEDE7F6),
          ),
          if (taps is int) ...[
            const SizedBox(width: 10),
            _pill('$taps tap${taps == 1 ? '' : 's'}',
                color: const Color(0xFFEDE7F6)),
          ],
        ],
      ),
    );
  }

  Widget _pill(String text, {required Color color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xB3000000),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color),
    ),
  );
}
