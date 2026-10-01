import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../model/phone_layout.dart';
import 'client_session.dart';

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
      ..anchor = Anchor.center
      ..zoom = l.logicalPxPerWorldUnit
      ..angle = l.turnRadians
      ..position = Vector2(l.worldCenterX, l.worldCenterY);
  }

  @override
  void update(double dt) {
    super.update(dt);
    _applyLayout();
    _lastDtMs = dt * 1000;
  }

  double get lastDtMs => _lastDtMs;
}

class _GameSurface extends Component {
  _GameSurface(this.game);

  final ViewportGame game;

  @override
  void render(Canvas canvas) {
    final session = game.session;
    final view = session.view;
    if (view == null) return;

    final frame = session.frameAt(game.lastDtMs);
    if (frame == null) return;

    view.render(canvas, frame);
  }
}
