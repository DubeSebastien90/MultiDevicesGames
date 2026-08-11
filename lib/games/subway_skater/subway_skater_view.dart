import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../sdk/contract/entity.dart';
import '../../sdk/contract/view.dart';
import '../../sdk/model/player_color.dart';
import 'subway_skater_config.dart';

/// The corridor, drawn the same on every phone because every phone is drawing
/// the same world.
///
/// Nothing here is per-phone except the highlight on your own circle and the
/// HUD — the lane markings are computed from the shared board and the dashes
/// scroll on the shared clock, so the corridor runs unbroken across the seams
/// rather than restarting at each phone.
class SubwaySkaterView extends GameView {
  SubwaySkaterView(this.context);

  final ViewContext context;

  static const _void = Color(0xFF05070D);
  static const _floor = Color(0xFF101A2E);
  static const _rail = Color(0xFF3D5A8A);
  static const _laneMark = Color(0x40C7E0FF);
  static const _hazard = Color(0xFFFF6B3D);
  static const _hazardCore = Color(0xFF7A2410);
  static const _me = Color(0xFFFFFFFF);
  static const _charge = Color(0xFFFFD166);

  final _paint = Paint();
  final _stroke = Paint()..style = PaintingStyle.stroke;

  /// Who is mid-tumble, and who is standing where, unpacked from shared state
  /// only when it changes.
  ///
  /// The wire carries joined strings — see the sim for why they are not lists —
  /// and splitting them sixty times a second to answer questions whose answers
  /// change a handful of times a round would be work for nothing.
  String _tumblingRaw = '';
  Set<String> _tumbling = const {};
  String _chargingRaw = '';
  Set<String> _charging = const {};
  String _orderRaw = '';
  List<String> _order = const [];
  String _phonesRaw = '';
  List<String> _phones = const [];

  @override
  void render(Canvas canvas, Frame frame) {
    _readShared(frame);

    _drawCorridor(canvas, frame);
    for (final o in frame.ofKind('obstacle')) {
      _drawObstacle(canvas, o);
    }
    for (final b in frame.ofKind('burst')) {
      _drawBurst(canvas, frame, b);
    }

    // The circle this phone's swipes move: the one standing in this phone's
    // place in the line, whoever it belongs to. Not the one that shares this
    // phone's id — that one is somewhere else the moment the order churns, and
    // ringing it would point every player at the wrong screen.
    final mine = postOf(frame.me.phoneId, _phones, _order).owner;
    for (final s in frame.ofKind('skater')) {
      _drawSkater(canvas, frame, s, steered: s.props['phone'] == mine);
    }
  }

  /// This phone's place in the line, and whose circle is standing in it.
  ///
  /// [owner] is null for a phone past the end of a line that has got shorter —
  /// nobody is standing there and nothing this screen is touched with moves.
  ///
  /// Read from the broadcast rather than from this device's own layout, and
  /// answered here for the canvas and the HUD both: those two disagreeing about
  /// which circle is yours is the one thing this game cannot survive, since the
  /// ring is the only thing telling a player which phone to reach for.
  static ({int place, String? owner}) postOf(
    String? phoneId,
    List<String> phones,
    List<String> order,
  ) {
    final place = phones.indexOf(phoneId ?? '');
    final standing = place >= 0 && place < order.length;
    return (place: place, owner: standing ? order[place] : null);
  }

  void _readShared(Frame frame) {
    final tumbling = frame.sharedState['tumbling'] as String? ?? '';
    if (tumbling != _tumblingRaw) {
      _tumblingRaw = tumbling;
      _tumbling = tumbling.isEmpty ? const {} : tumbling.split(',').toSet();
    }

    final charging = frame.sharedState['charging'] as String? ?? '';
    if (charging != _chargingRaw) {
      _chargingRaw = charging;
      _charging = charging.isEmpty ? const {} : charging.split(',').toSet();
    }

    final order = frame.sharedState['order'] as String? ?? '';
    if (order != _orderRaw) {
      _orderRaw = order;
      _order = order.isEmpty ? const [] : order.split(',');
    }

    final phones = frame.sharedState['phones'] as String? ?? '';
    if (phones != _phonesRaw) {
      _phonesRaw = phones;
      _phones = phones.isEmpty ? const [] : phones.split(',');
    }
  }

  /// Floor, rails and lane markings, clipped to what this screen can see.
  void _drawCorridor(Canvas canvas, Frame frame) {
    final view = frame.visible.inflate(2);
    final board = frame.board;

    _paint.color = _void;
    canvas.drawRect(
      Rect.fromLTWH(view.left, view.top, view.width, view.height),
      _paint,
    );

    final left = math.max(view.left, board.left);
    final right = math.min(view.right, board.right);
    if (right <= left) return;

    _paint.color = _floor;
    canvas.drawRect(
      Rect.fromLTRB(left, board.top, right, board.bottom),
      _paint,
    );

    _stroke
      ..color = _rail
      ..strokeWidth = frame.onePixel * 2;
    canvas.drawLine(
      Offset(left, board.top),
      Offset(right, board.top),
      _stroke,
    );
    canvas.drawLine(
      Offset(left, board.bottom),
      Offset(right, board.bottom),
      _stroke,
    );

    _drawLaneDashes(canvas, frame, left, right);
  }

  /// Dashes between the lanes, sliding down the corridor at the speed the
  /// obstacles travel — so the floor visibly winds up as the round does.
  ///
  /// Phased on `frame.timeMs`, which is the host's clock and identical on every
  /// phone: a local clock here would have the dashes step across each seam. And
  /// on [SubwaySkaterConfig.travelAt] rather than on a running total, for the
  /// same reason — a sum of per-frame steps is a different number on a phone
  /// that dropped a frame.
  void _drawLaneDashes(Canvas canvas, Frame frame, double left, double right) {
    const period = 3.0;
    const dash = 1.6;

    final phase = SubwaySkaterConfig.travelAt(frame.timeMs / 1000) % period;
    final board = frame.board;

    _stroke
      ..color = _laneMark
      ..strokeWidth = frame.onePixel * 1.5;

    for (var lane = 1; lane < SubwaySkaterConfig.lanes; lane++) {
      final y = board.top + board.height * lane / SubwaySkaterConfig.lanes;
      // Start at the first dash at or before the visible left edge, so what is
      // drawn depends only on world position and never on where this screen is.
      var x = (left / period).floorToDouble() * period + phase - period;
      while (x < right) {
        final a = math.max(x, left);
        final b = math.min(x + dash, right);
        if (b > a) canvas.drawLine(Offset(a, y), Offset(b, y), _stroke);
        x += period;
      }
    }
  }

  void _drawObstacle(Canvas canvas, RenderEntity o) {
    final w = o.propDouble('w', SubwaySkaterConfig.obstacleLength);
    final h = o.propDouble('h', 1);
    final rect =
        Rect.fromCenter(center: Offset(o.x, o.y), width: w, height: h);
    final rounded = RRect.fromRectXY(rect, h * 0.25, h * 0.25);

    _paint.color = _hazard;
    canvas.drawRRect(rounded, _paint);

    // A dark core, so a block reads as solid rather than as a glowing pill —
    // and so the leading edge, which is the part you are timing, is the
    // brightest thing on it.
    _paint.color = _hazardCore;
    canvas.drawRRect(
      RRect.fromRectXY(rect.deflate(h * 0.22), h * 0.12, h * 0.12),
      _paint,
    );
  }

  /// What a flattened block leaves behind: a ring going out and five shards
  /// going with it, both fading.
  ///
  /// Timed from the birth stamp in the entity's own props against the shared
  /// clock, so the shatter plays at the same instant on every screen that can
  /// see it — and, on a burst straddling a seam, at the same instant on both
  /// halves of itself.
  void _drawBurst(Canvas canvas, Frame frame, RenderEntity b) {
    final life = SubwaySkaterConfig.burstSeconds * 1000;
    final t = ((frame.timeMs - b.propDouble('born')) / life).clamp(0.0, 1.0);
    if (t >= 1) return;

    final size = b.propDouble('size', 1);
    // Out fast and then easing off, which is what a thing coming apart does.
    final spread = 1 - (1 - t) * (1 - t);
    final fade = 1 - t;

    _stroke
      ..color = _charge.withValues(alpha: 0.8 * fade)
      ..strokeWidth = frame.onePixel * 2;
    canvas.drawCircle(Offset(b.x, b.y), size * (0.3 + 1.5 * spread), _stroke);

    _paint.color = _hazard.withValues(alpha: fade);
    final shard = size * 0.26 * fade;
    for (var i = 0; i < 5; i++) {
      // Tilted per burst, so five of them in a row do not look like one sprite
      // played five times.
      final a = b.angle + i * 2 * math.pi / 5;
      final at = Offset(b.x, b.y) +
          Offset(math.cos(a), math.sin(a)) * (size * (0.2 + 1.7 * spread));
      canvas.drawRect(
        Rect.fromCenter(center: at, width: shard * 2, height: shard * 2),
        _paint,
      );
    }
  }

  void _drawSkater(
    Canvas canvas,
    Frame frame,
    RenderEntity s, {
    required bool steered,
  }) {
    final r = s.propDouble('r', SubwaySkaterConfig.skaterRadius);
    final phoneId = s.props['phone'] as String?;
    final down = phoneId != null && _tumbling.contains(phoneId);
    final charged = phoneId != null && _charging.contains(phoneId);

    final color = PlayerPalette.byId(s.props['color'] as String?)?.value ??
        const Color(0xFFF2F4F8);
    final center = Offset(s.x, s.y);

    // Fresh off a promotion: a halo, because for the next second this circle
    // goes through blocks instead of being stopped by them, and everybody at
    // the table needs to be able to see that from where they are sitting.
    if (charged) {
      _paint.color = _charge.withValues(alpha: 0.28);
      canvas.drawCircle(center, r * 2.1, _paint);
      _paint.color = _charge.withValues(alpha: 0.5);
      canvas.drawCircle(center, r * 1.5, _paint);
    }

    _paint.color = down ? color.withValues(alpha: 0.55) : color;
    canvas.drawCircle(center, r, _paint);

    // Spokes, turned by the entity's own angle. Still on a skater standing up,
    // spinning on one being carried away — which is how a tumble reads from the
    // far end of the table, where the circle is too small to show anything else.
    _stroke
      ..color = const Color(0x66000000)
      ..strokeWidth = frame.onePixel * 1.5;
    for (var i = 0; i < 3; i++) {
      final a = s.angle + i * math.pi / 3;
      canvas.drawLine(
        center + Offset(math.cos(a), math.sin(a)) * (r * 0.35),
        center + Offset(math.cos(a), math.sin(a)) * (r * 0.92),
        _stroke,
      );
    }

    if (!steered) return;
    // The circle this screen's swipes move. Ordinarily it is standing right
    // here — the ring is on your own glass — and it follows the circle away
    // while that one is being carried off, which is the clearest way to say
    // "this is still the one you are driving".
    _stroke
      ..color = _me
      ..strokeWidth = frame.onePixel * 2.5;
    canvas.drawCircle(center, r * 1.45, _stroke);
  }

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    if (frame.sharedState['over'] == true) return null;

    List<String> read(String key) => (frame.sharedState[key] as String? ?? '')
        .split(',')
        .where((id) => id.isNotEmpty)
        .toList();

    final order = read('order');
    final post = postOf(frame.phoneId, read('phones'), order);

    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (post.owner != null)
            Text(
              // This phone's place in the line, which is fixed — the leftmost
              // phone is always the front. What changes is who is standing at
              // it, and that is worth saying out loud, because the number is
              // also what the place is paying whoever is there.
              '${_ordinal(post.place + 1)} of ${order.length}',
              style: TextStyle(
                color: post.place == 0
                    ? const Color(0xFFFFD166)
                    : const Color(0xCCFFFFFF),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            const Text(
              // A phone past the end of a line that has got shorter. Nobody is
              // standing here, so nothing this screen is touched with moves.
              'out of the line',
              style: TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
            ),
          const SizedBox(width: 10),
          Text(
            '${frame.sharedState['secondsLeft']} s',
            style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
          ),
        ],
      ),
    );
  }

  static String _ordinal(int n) {
    if (n % 100 >= 11 && n % 100 <= 13) return '${n}th';
    return switch (n % 10) {
      1 => '${n}st',
      2 => '${n}nd',
      3 => '${n}rd',
      _ => '${n}th',
    };
  }
}
