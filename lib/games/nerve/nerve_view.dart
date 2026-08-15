import 'dart:math' as math;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import 'nerve_config.dart';

/// Dark, until it is your turn — then it glows a little brighter for every
/// second you dare to keep your finger down.
///
/// The glow is driven from [Frame.sharedState]'s whole-second `heldSeconds`,
/// never a locally kept clock: two phones timing the same hold independently
/// would drift, and the one holding it is exactly the phone that must not be
/// wrong about how far it has gone.
class NerveView extends GameView {
  NerveView(this.context);

  final ViewContext context;

  static const _dark = Color(0xFF05070D);
  static const _hold = Color(0xFFFFB300);
  static const _bank = Color(0xFF33D17A);
  static const _burst = Color(0xFFFF3B30);

  final _fill = Paint();

  int _seenBank = 0;
  int _seenBurst = 0;
  double _flashLeftMs = 0;
  Color _flashColor = _bank;

  @override
  void render(Canvas canvas, Frame frame) {
    final me = frame.me.phoneId;
    _trackBank(frame, me);
    _trackBurst(frame, me);
    _flashLeftMs = math.max(0, _flashLeftMs - frame.dt * 1000);

    final area = frame.visible.inflate(2);
    final rect = Rect.fromLTWH(area.left, area.top, area.width, area.height);

    final myTurn = frame.sharedState['current'] == me;
    final holding = myTurn && frame.sharedState['holding'] == true;
    _fill.color = holding ? _holdColor(frame) : _dark;
    canvas.drawRect(rect, _fill);

    _drawFlash(canvas, rect);
  }

  /// Warmer the longer the held streak runs, so the risk reads on the glass
  /// itself rather than only in a number underneath it.
  Color _holdColor(Frame frame) {
    final held = (frame.sharedState['heldSeconds'] as num?)?.toInt() ?? 0;
    final t = (held / NerveConfig.maxBurstSeconds).clamp(0.0, 1.0);
    return Color.lerp(_hold.withValues(alpha: 0.35), _hold, t)!;
  }

  void _trackBank(Frame frame, String me) {
    final seq = (frame.sharedState['bankSeq'] as num?)?.toInt() ?? 0;
    if (seq < _seenBank) _seenBank = 0;
    if (seq > _seenBank) {
      _seenBank = seq;
      if (frame.sharedState['bankBy'] == me) {
        _flashLeftMs = NerveConfig.flashMs;
        _flashColor = _bank;
      }
    }
  }

  void _trackBurst(Frame frame, String me) {
    final seq = (frame.sharedState['burstSeq'] as num?)?.toInt() ?? 0;
    if (seq < _seenBurst) _seenBurst = 0;
    if (seq > _seenBurst) {
      _seenBurst = seq;
      if (frame.sharedState['burstBy'] == me) {
        _flashLeftMs = NerveConfig.flashMs;
        _flashColor = _burst;
        HapticFeedback.vibrate();
      }
    }
  }

  void _drawFlash(Canvas canvas, Rect area) {
    if (_flashLeftMs <= 0) return;
    final t = _flashLeftMs / NerveConfig.flashMs;
    _fill.color = _flashColor.withValues(alpha: 0.4 * t);
    canvas.drawRect(area, _fill);
  }

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    if (frame.sharedState['over'] == true) return null;

    final mine = frame.sharedState['current'] == frame.phoneId;
    final holding = mine && frame.sharedState['holding'] == true;
    final label = holding
        ? 'Let go to bank it — or keep going'
        : mine
        ? 'YOUR TURN — press and hold'
        : '${frame.sharedState['secondsLeft']} s left';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: mine ? _hold : const Color(0xFFF2F4F8),
        ),
      ),
    );
  }
}
