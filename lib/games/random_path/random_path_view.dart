import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';

/// A blank screen and a countdown.
///
/// Deliberately empty: everything worth seeing in this round is on the
/// placement screen before it — the path, and the coloured edges that say which
/// phone goes against which.
class RandomPathView extends GameView {
  RandomPathView(this.context);

  final ViewContext context;

  static const _dark = Color(0xFF05070D);

  final _fill = Paint()..color = _dark;

  @override
  void render(Canvas canvas, Frame frame) {
    final area = frame.visible.inflate(2);
    canvas.drawRect(
      Rect.fromLTWH(area.left, area.top, area.width, area.height),
      _fill,
    );
  }

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) => Text(
    frame.sharedState['over'] == true
        ? 'Done'
        : '${frame.sharedState['secondsLeft']}',
    style: const TextStyle(color: Color(0x66FFFFFF), fontSize: 12),
  );
}
