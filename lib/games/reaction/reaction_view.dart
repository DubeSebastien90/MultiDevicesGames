import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/model/player_color.dart';
import 'reaction_config.dart';

/// Black, until a dot in your colour appears somewhere on your screen.
///
/// A spot rather than the whole panel on purpose: a screen changing colour is
/// caught with the corner of an eye from across the table, so filling it would
/// have measured how long a *neighbour* took to notice. A dot has to be found
/// on your own phone, which is the thing the game claims to be timing.
///
/// Getting it wrong buzzes the phone and rims the screen in red. Both are for
/// the player who fumbled and nobody else — the table can hear a buzz, but only
/// one person has to know which of the two mistakes it was.
class ReactionView extends GameView {
  ReactionView(this.context);

  final ViewContext context;

  static const _dark = Color(0xFF05070D);
  static const _fault = Color(0xFFFF3B30);

  final _fill = Paint();
  final _rim = Paint()..style = PaintingStyle.stroke;

  /// The last mistake this phone knows about, and when it was noticed.
  ///
  /// Local, and deliberately so. Everything the platform insists be driven by
  /// the shared clock is something two screens have to agree about; this is one
  /// phone's own apology to the person holding it, and no other screen shows it
  /// at all.
  int _seenFaults = 0;
  double _flashUntilMs = 0;

  @override
  void render(Canvas canvas, Frame frame) {
    final area = frame.visible.inflate(2);
    _fill.color = _dark;
    canvas.drawRect(
      Rect.fromLTWH(area.left, area.top, area.width, area.height),
      _fill,
    );

    _noticeFaults(frame);

    final lit = frame.sharedState['lit'] as String?;
    if (lit == frame.me.phoneId) _drawDot(canvas, frame);

    _drawFaultRim(canvas, frame);
  }

  void _drawDot(Canvas canvas, Frame frame) {
    final x = (frame.sharedState['dotX'] as num?)?.toDouble();
    final y = (frame.sharedState['dotY'] as num?)?.toDouble();
    if (x == null || y == null) return;

    final r = (frame.sharedState['dotR'] as num?)?.toDouble() ??
        ReactionConfig.dotRadiusWorld;
    final id = frame.sharedState['litColor'] as String?;
    // A phone with no colour still has to be visibly lit, or its turn silently
    // does not happen.
    _fill.color = PlayerPalette.byId(id)?.value ?? const Color(0xFFF2F4F8);
    canvas.drawCircle(Offset(x, y), r, _fill);
  }

  /// The buzz, once per mistake.
  void _noticeFaults(Frame frame) {
    final faults = frame.sharedState['faults'];
    final mine = faults is Map
        ? ((faults[frame.me.phoneId] as num?)?.toInt() ?? 0)
        : 0;
    // Going down means the round was reset, which is not a mistake to buzz
    // about — just catch up quietly.
    if (mine <= _seenFaults) {
      _seenFaults = mine;
      return;
    }

    _seenFaults = mine;
    _flashUntilMs = frame.timeMs + ReactionConfig.faultFlashMs;
    HapticFeedback.heavyImpact();
  }

  /// A red edge, fading out. Around the rim rather than over the middle so it
  /// cannot be mistaken for the dot it is telling you that you missed.
  void _drawFaultRim(Canvas canvas, Frame frame) {
    final left = _flashUntilMs - frame.timeMs;
    if (left <= 0) return;

    final fade = (left / ReactionConfig.faultFlashMs).clamp(0.0, 1.0);
    final screen = frame.me.viewport;
    final width = frame.onePixel * 14;

    _rim
      ..color = _fault.withValues(alpha: 0.55 * fade)
      ..strokeWidth = width;

    // Inset by half the stroke, or half of it falls outside the glass.
    final inset = width / 2;
    canvas.drawRect(
      Rect.fromLTWH(
        screen.left + inset,
        screen.top + inset,
        screen.width - width,
        screen.height - width,
      ),
      _rim,
    );
  }

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    if (frame.sharedState['over'] == true) return null;

    // On the lit phone the countdown is one more thing between the eye and the
    // dot, so it goes away exactly when it would be a distraction.
    if (frame.sharedState['lit'] == frame.phoneId) return null;

    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        '${frame.sharedState['secondsLeft']} s',
        style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
      ),
    );
  }
}
