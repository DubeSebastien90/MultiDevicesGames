import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../model/phone_layout.dart';
import 'client_session.dart';

/// Renders this phone's slice of the shared world by handing the canvas to the
/// game's own [GameView].
///
/// The camera is not a creative choice: [PhoneLayout.logicalPxPerWorldUnit] is
/// set so one world unit occupies its true physical size on *this* panel, and
/// the viewfinder's top-left is pinned to this phone's world offset. Two phones
/// with different resolutions and densities therefore draw the same world at the
/// same real-world scale, which is the whole reason the seam can line up.
///
/// The platform owns this much and no more. What gets painted inside that
/// transform is entirely the game's business.
class ViewportGame extends FlameGame {
  ViewportGame({required this.session});

  final ClientSession session;

  PhoneLayout? _appliedLayout;
  double _lastDtMs = 16;

  @override
  Color backgroundColor() => const Color(0xFF0B1020);

  @override
  Future<void> onLoad() async {
    world.add(_GameSurface(this));
    _applyLayout();
  }

  void _applyLayout() {
    final l = session.layout;
    if (l == null || l == _appliedLayout) return;
    _appliedLayout = l;
    camera.viewfinder
      ..anchor = Anchor.topLeft
      ..zoom = l.logicalPxPerWorldUnit
      ..position = Vector2(l.worldOffsetX, l.worldOffsetY);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _applyLayout();
    _lastDtMs = dt * 1000;
  }

  double get lastDtMs => _lastDtMs;
}

/// The one component in the tree: it advances the shared timeline and lets the
/// game paint that instant.
class _GameSurface extends Component {
  _GameSurface(this.game);

  final ViewportGame game;

  @override
  void render(Canvas canvas) {
    final session = game.session;
    final view = session.view;
    if (view == null) return;

    // Walk the shared timeline forward, then read this instant off it. Every
    // phone sampling the same instant gets the same answer.
    final frame = session.frameAt(game.lastDtMs);
    if (frame == null) return;

    view.render(canvas, frame);
  }
}
