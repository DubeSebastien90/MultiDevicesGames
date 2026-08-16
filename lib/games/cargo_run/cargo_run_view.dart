import 'package:flutter/widgets.dart';

import '../../sdk/contract/view.dart';
import '../../sdk/render/shape_view.dart';
import 'cargo_run_config.dart';

/// Cargo Run's pixels: a belt, and whatever is rolling down it.
///
/// The crates draw themselves for free — [ShapeView] paints a box from
/// `shape`/`w`/`h`/`color`, which is the whole of a crate's appearance — so
/// this only adds the lane the belt runs along and a HUD for the score and
/// clock.
class CargoRunView extends ShapeView {
  CargoRunView(this.context)
    : super(
        background: const Color(CargoRunConfig.colorBackground),
        playfield: const Color(CargoRunConfig.colorPlayfield),
      );

  final ViewContext context;

  final _fill = Paint()..isAntiAlias = true;

  @override
  void renderBackground(Canvas canvas, Frame frame) {
    super.renderBackground(canvas, frame);

    final board = frame.board;
    _fill.color = const Color(CargoRunConfig.colorLane);
    canvas.drawRect(
      Rect.fromLTWH(
        board.left,
        board.centerY - CargoRunConfig.crateRadius * 1.6,
        board.width,
        CargoRunConfig.crateRadius * 3.2,
      ),
      _fill,
    );
  }

  @override
  Widget? buildHud(BuildContext context, HudFrame frame) {
    final me = frame.scores.entryFor(frame.phoneId);
    final secondsLeft = frame.sharedState['secondsLeft'];

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xB3000000),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${me?.total ?? 0}',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFFFFFF),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (secondsLeft is int)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xB3000000),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${secondsLeft}s',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: secondsLeft <= 10
                      ? const Color(0xFFFF6B6B)
                      : const Color(0xFFDDE6D8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
