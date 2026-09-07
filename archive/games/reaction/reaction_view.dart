import 'dart:math' as math;

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
/// Getting it wrong buzzes the phone and washes the edges red. Both are for the
/// player who fumbled and nobody else — the table can hear a buzz, but only one
/// person has to know which of the two mistakes it was.
class ReactionView extends GameView {
  ReactionView(this.context);

  final ViewContext context;

  static const _dark = Color(0xFF05070D);
  static const _fault = Color(0xFFFF3B30);

  final _fill = Paint();
  final _glow = Paint();

  /// The last mistake this phone knows about, and how much of the wash is left.
  ///
  /// Local, and deliberately so. Everything the platform insists be driven by
  /// the shared clock is something two screens have to agree about; this is one
  /// phone's own apology to the person holding it, and no other screen shows it
  /// at all.
  ///
  /// A countdown rather than "the instant it started", which is what this was
  /// and what made it wrong: `frame.timeMs` is the *round's* clock and goes back
  /// to zero at every new one. A stored timestamp therefore came round again a
  /// few seconds into the next game, and phones that had fumbled in the last one
  /// all lit up red together with nobody having touched anything.
  int _seenFault = 0;
  double _flashLeftMs = 0;

  /// Whether the red wash is showing. For tests — the effect is otherwise
  /// invisible to anything but an eye.
  bool get isFlashing => _flashLeftMs > 0;

  @override
  void render(Canvas canvas, Frame frame) {
    final area = frame.visible.inflate(2);
    _fill.color = _dark;
    canvas.drawRect(
      Rect.fromLTWH(area.left, area.top, area.width, area.height),
      _fill,
    );

    // Counted down from the local frame delta, which only ever moves forward.
    _flashLeftMs = math.max(0, _flashLeftMs - frame.dt * 1000);
    _noticeFault(frame);

    if (frame.sharedState['lit'] == frame.me.phoneId) _drawDot(canvas, frame);

    _drawFaultGlow(canvas, frame);
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

  /// The buzz, once per mistake, and only for the phone that made it.
  void _noticeFault(Frame frame) {
    final seq = (frame.sharedState['faultSeq'] as num?)?.toInt() ?? 0;

    // Going down means the round was reset, which is nothing to buzz about —
    // and anything still on screen belongs to a round that is over.
    if (seq <= _seenFault) {
      if (seq < _seenFault) _flashLeftMs = 0;
      _seenFault = seq;
      return;
    }
    _seenFault = seq;

    if (frame.sharedState['faultBy'] != frame.me.phoneId) return;

    _flashLeftMs = ReactionConfig.faultFlashMs;
    // Deliberately the long-press buzz rather than a light impact: this has to
    // be felt by somebody whose attention is on the table, through a phone lying
    // flat on it. The subtle ones are for confirming a button press.
    HapticFeedback.vibrate();
  }

  /// A red wash that swells in from the edges and ebbs away.
  ///
  /// Four bands, each fading to nothing as it reaches inward, so the middle of
  /// the screen — where the dot appears — is never covered. The corners overlap
  /// and sit slightly deeper, which is what the eye expects from a vignette.
  void _drawFaultGlow(Canvas canvas, Frame frame) {
    if (_flashLeftMs <= 0) return;
    final t = 1 - _flashLeftMs / ReactionConfig.faultFlashMs;

    final alpha = 0.75 * _envelope(t);
    if (alpha <= 0.004) return;

    final screen = frame.me.viewport;
    final depth =
        math.min(screen.width, screen.height) * ReactionConfig.faultEdgeFraction;
    final colors = [
      _fault.withValues(alpha: alpha),
      _fault.withValues(alpha: 0),
    ];

    void band(Rect rect, Alignment from, Alignment to) {
      _glow.shader = LinearGradient(begin: from, end: to, colors: colors)
          .createShader(rect);
      canvas.drawRect(rect, _glow);
    }

    band(
      Rect.fromLTWH(screen.left, screen.top, screen.width, depth),
      Alignment.topCenter,
      Alignment.bottomCenter,
    );
    band(
      Rect.fromLTWH(
          screen.left, screen.bottom - depth, screen.width, depth),
      Alignment.bottomCenter,
      Alignment.topCenter,
    );
    band(
      Rect.fromLTWH(screen.left, screen.top, depth, screen.height),
      Alignment.centerLeft,
      Alignment.centerRight,
    );
    band(
      Rect.fromLTWH(
          screen.right - depth, screen.top, depth, screen.height),
      Alignment.centerRight,
      Alignment.centerLeft,
    );

    _glow.shader = null;
  }

  /// Nothing to full and back again: a quick swell, a longer ebb.
  ///
  /// Asymmetric on purpose. A mistake should register immediately — the buzz and
  /// the colour arriving together — and then let go slowly enough to be seen
  /// rather than merely glimpsed.
  static double _envelope(double t) {
    const attack = 0.18;
    if (t < attack) {
      final x = t / attack;
      return x * x * (3 - 2 * x); // smooth in, no hard edge at the start
    }
    final x = (t - attack) / (1 - attack);
    return (1 - x) * (1 - x); // and away, easing out
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
