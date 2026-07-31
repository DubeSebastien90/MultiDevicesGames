/// Wire protocol for the multiscreen prototype.
///
/// Everything is JSON over a [Transport]. Message shapes are kept flat and
/// data-ish on purpose: a later "downloadable game definition" layer should be
/// able to describe entities without new message types.
library;

/// Client -> Host.
class ClientMsg {
  /// First message on a fresh connection: carries the 5-digit join code. The
  /// host answers nothing else until this one checks out.
  static const join = 'join';
  static const calibration = 'calibration';
  static const confirmPlacement = 'confirmPlacement';
  static const touch = 'touch';
  static const ping = 'ping';
  static const reset = 'reset';
}

/// Host -> Client.
class HostMsg {
  static const welcome = 'welcome';
  static const lobby = 'lobby';
  static const layout = 'layout';
  static const worldInit = 'worldInit';
  static const start = 'start';
  static const state = 'state';
  static const pong = 'pong';
}

/// Touch phases, mirroring pointer events.
class TouchPhase {
  static const down = 'down';
  static const move = 'move';
  static const up = 'up';
}

/// Shape kinds understood by the renderer. Kept as data so the host can
/// describe a world the client has no compiled-in knowledge of.
class ShapeKind {
  static const circle = 'circle';
  static const box = 'box';
}

/// A single entity's static description, sent once in [HostMsg.worldInit].
class EntitySpec {
  const EntitySpec({
    required this.id,
    required this.shape,
    required this.radius,
    required this.width,
    required this.height,
    required this.colorValue,
    this.role = 'prop',
  });

  final String id;
  final String shape;

  /// World units. Only meaningful for [ShapeKind.circle].
  final double radius;

  /// World units. Only meaningful for [ShapeKind.box].
  final double width;
  final double height;

  /// ARGB value; the host picks colours so all screens agree.
  final int colorValue;

  /// Free-form tag ('bird', 'target', 'ground', 'prop') for renderer accents.
  final String role;

  Map<String, dynamic> toJson() => {
    'id': id,
    'shape': shape,
    if (shape == ShapeKind.circle) 'r': radius,
    if (shape == ShapeKind.box) 'w': width,
    if (shape == ShapeKind.box) 'h': height,
    'color': colorValue,
    'role': role,
  };

  static EntitySpec fromJson(Map<String, dynamic> j) => EntitySpec(
    id: j['id'] as String,
    shape: j['shape'] as String,
    radius: (j['r'] as num?)?.toDouble() ?? 0,
    width: (j['w'] as num?)?.toDouble() ?? 0,
    height: (j['h'] as num?)?.toDouble() ?? 0,
    colorValue: (j['color'] as num).toInt(),
    role: (j['role'] as String?) ?? 'prop',
  );
}

/// One entity's transform at a given tick.
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

  /// Short keys: this rides the wire 60 times a second.
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

  /// Trim to 0.001 world units (= 10 micrometres at the v1 scale). Well below
  /// what any screen can show, and it keeps snapshots small.
  static double _r(double v) => (v * 1000).roundToDouble() / 1000;
}

/// The slingshot band, broadcast so *every* screen draws the same pull.
class SlingState {
  const SlingState({
    required this.active,
    required this.anchorX,
    required this.anchorY,
    required this.pullX,
    required this.pullY,
    this.draggingPhoneId,
  });

  final bool active;
  final double anchorX;
  final double anchorY;
  final double pullX;
  final double pullY;
  final String? draggingPhoneId;

  Map<String, dynamic> toJson() => {
    'active': active,
    'ax': anchorX,
    'ay': anchorY,
    'px': pullX,
    'py': pullY,
    if (draggingPhoneId != null) 'by': draggingPhoneId,
  };

  static SlingState fromJson(Map<String, dynamic> j) => SlingState(
    active: j['active'] as bool,
    anchorX: (j['ax'] as num).toDouble(),
    anchorY: (j['ay'] as num).toDouble(),
    pullX: (j['px'] as num).toDouble(),
    pullY: (j['py'] as num).toDouble(),
    draggingPhoneId: j['by'] as String?,
  );
}
