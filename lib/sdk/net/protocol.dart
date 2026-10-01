library;

class ClientMsg {
  static const join = 'join';
  static const calibration = 'calibration';

  static const pickColor = 'pickColor';

  static const confirmPlacement = 'confirmPlacement';

  static const poke = 'poke';
  static const touch = 'touch';
  static const ping = 'ping';
  static const reset = 'reset';

  static const interrupted = 'interrupted';
}

class HostMsg {
  static const welcome = 'welcome';
  static const lobby = 'lobby';
  static const layout = 'layout';

  static const worldInit = 'worldInit';

  static const spawn = 'spawn';

  static const despawn = 'despawn';

  static const start = 'start';

  static const state = 'state';

  static const shared = 'shared';

  static const scores = 'scores';

  static const outcome = 'outcome';

  static const sitOut = 'sitOut';

  static const nameDropSuspected = 'nameDropSuspected';

  static const sound = 'sound';

  static const poke = 'poke';

  static const pong = 'pong';
}

class EntityState {
  const EntityState({
    required this.id,
    required this.x,
    required this.y,
    required this.angle,
    required this.vx,
    required this.vy,
  });

  final String id;
  final double x;
  final double y;
  final double angle;
  final double vx;
  final double vy;

  Map<String, dynamic> toJson() => {
    'id': id,
    'x': _r(x),
    'y': _r(y),
    'a': _r(angle),
    'vx': _r(vx),
    'vy': _r(vy),
  };

  static EntityState fromJson(Map<String, dynamic> j) => EntityState(
    id: j['id'] as String,
    x: (j['x'] as num).toDouble(),
    y: (j['y'] as num).toDouble(),
    angle: (j['a'] as num).toDouble(),
    vx: (j['vx'] as num).toDouble(),
    vy: (j['vy'] as num).toDouble(),
  );

  static double _r(double v) => (v * 1000).roundToDouble() / 1000;
}
