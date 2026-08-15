import 'dart:math' as math;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import 'tandem_config.dart';

/// Dark, until this screen is one half of a lit pair.
///
/// A screen lighting up alone means nothing here — the whole idea is that
/// *two* screens go bright together and a shrinking ring gives them a moment
/// to both be tapped. Tapping first does not finish it: the fill dims to say
/// "your partner hasn't gone yet" rather than turning this into a race.
class TandemView extends GameView {
  TandemView(this.context);

  final ViewContext context;

  static const _dark = Color(0xFF0B1023);
  static const _lit = Color(0xFFFFC857);
  static const _waiting = Color(0xFF7A5B1E);
  static const _success = Color(0xFF34D399);
  static const _miss = Color(0xFFEF4444);

  final _fill = Paint();
  final _ring = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  int _seenResultSeq = 0;
  double _flashLeftMs = 0;
  bool _flashIsSuccess = true;

  @override
  void render(Canvas canvas, Frame frame) {
    final area = frame.visible.inflate(2);
    final me = frame.me.phoneId;
    final litA = frame.sharedState['litA'] as String?;
    final litB = frame.sharedState['litB'] as String?;
    final isLit = me == litA || me == litB;
    final tappedMe = (me == litA && frame.sharedState['tappedA'] == true) ||
        (me == litB && frame.sharedState['tappedB'] == true);

    _flashLeftMs = math.max(0, _flashLeftMs - frame.dt * 1000);
    _noticeResult(frame);

    _fill.color = _flashLeftMs > 0
        ? (_flashIsSuccess ? _success : _miss)
        : isLit
            ? (tappedMe ? _waiting : _lit)
            : _dark;
    canvas.drawRect(
      Rect.fromLTWH(area.left, area.top, area.width, area.height),
      _fill,
    );

    if (isLit && _flashLeftMs <= 0) _drawWindowRing(canvas, frame);
  }

  void _drawWindowRing(Canvas canvas, Frame frame) {
    final left = (frame.sharedState['windowLeft'] as num?)?.toDouble();
    if (left == null) return;
    final fraction =
        (left / TandemConfig.windowSeconds).clamp(0.0, 1.0);

    final screen = frame.me.viewport;
    final center = Offset(screen.centerX, screen.centerY);
    final radius = math.min(screen.width, screen.height) * 0.32;
    _ring
      ..color = const Color(0x66000000)
      ..strokeWidth = radius * 0.16;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * fraction,
      false,
      _ring,
    );
  }

  /// Flashes green for the pair that just synced, red for the pair that just
  /// missed — and only for the two phones the attempt was actually about.
  void _noticeResult(Frame frame) {
    final seq = (frame.sharedState['resultSeq'] as num?)?.toInt() ?? 0;
    if (seq <= _seenResultSeq) {
      if (seq < _seenResultSeq) _flashLeftMs = 0;
      _seenResultSeq = seq;
      return;
    }
    _seenResultSeq = seq;

    final me = frame.me.phoneId;
    if (me != frame.sharedState['resultA'] &&
        me != frame.sharedState['resultB']) {
      return;
    }

    _flashIsSuccess = frame.sharedState['resultWasSuccess'] == true;
    _flashLeftMs = TandemConfig.flashMs;
    if (_flashIsSuccess) HapticFeedback.lightImpact();
  }

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    if (frame.sharedState['over'] == true) return null;

    final me = frame.phoneId;
    final isLit =
        me == frame.sharedState['litA'] || me == frame.sharedState['litB'];

    final label = isLit
        ? 'TAP!'
        : '${frame.sharedState['successes']}/${frame.sharedState['target']}'
            '  ·  ${frame.sharedState['secondsLeft']}s';

    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        label,
        style: TextStyle(
          color: isLit ? const Color(0xFF0B1023) : const Color(0x99FFFFFF),
          fontSize: isLit ? 20 : 12,
          fontWeight: isLit ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
    );
  }
}
