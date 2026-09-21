import 'package:flutter/widgets.dart';

import '../../sdk/render/shape_view.dart';

/// Hot Potato's look: the default shapes, on a dark floor.
class HotPotatoView extends ShapeView {
  HotPotatoView() : super(grid: false, playfield: const Color(0xFF141C33));

  // No HUD. The fuse belongs on the potato — how long is left is a thing to
  // read off the object being passed around, not off a corner of the screen —
  // and a phone that has it does not need telling: it is the one with the
  // potato drawn on it.
}
