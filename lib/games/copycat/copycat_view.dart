import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import 'copycat_config.dart';

/// A block of colour per phone — dim until its turn, bright while it is lit.
///
/// No entities cross the seam here, so like Reaction Time this is driven
/// entirely from [Frame.sharedState]: a phone knows it is lit by comparing its
/// own id against `sharedState['lit']`, nothing else.
class CopycatView extends GameView {
  static const _dark = Color(0xFF05070D);

  final _fill = Paint();

  /// Deterministic per phone, so every screen picks its own tile colour
  /// without needing to know who else is on the board.
  Color _tileColorOf(String phoneId) {
    final index = phoneId.hashCode.abs() % CopycatConfig.palette.length;
    return Color(CopycatConfig.palette[index]);
  }

  @override
  void render(Canvas canvas, Frame frame) {
    final area = frame.visible.inflate(2);
    final rect = Rect.fromLTWH(area.left, area.top, area.width, area.height);

    final lit = frame.sharedState['lit'] == frame.me.phoneId;
    final tile = _tileColorOf(frame.me.phoneId);

    _fill.color = lit ? tile : Color.lerp(_dark, tile, CopycatConfig.dimAlpha)!;
    canvas.drawRect(rect, _fill);
  }

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final phase = frame.sharedState['phase'] as String?;
    final length = (frame.sharedState['length'] as num?)?.toInt() ?? 1;
    final target = (frame.sharedState['target'] as num?)?.toInt() ?? 1;
    final secondsLeft = (frame.sharedState['secondsLeft'] as num?)?.toInt();
    final lit = frame.sharedState['lit'] == frame.phoneId;

    final label = switch (phase) {
      'input' => lit ? "your turn!" : 'tap the pattern',
      _ => 'watch…',
    };

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          '$label   $length/$target'
          '${secondsLeft == null ? '' : '   ${secondsLeft}s'}',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF2F4F8),
          ),
        ),
      ),
    );
  }
}
