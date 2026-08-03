/// Anything with a position that the platform will keep in sync for you.
///
/// The split here is the load-bearing decision of the whole contract. [kind] and
/// [props] are declared once when an entity appears and never change; the
/// transform changes every tick and is the *only* thing interpolated. That is
/// what lets a game paint whatever it likes while the platform still guarantees
/// that two phones agree, to the millimetre, about where the thing is.
library;

/// The unchanging half of an entity, sent once when it first appears.
class EntityDescriptor {
  const EntityDescriptor({
    required this.id,
    required this.kind,
    this.props = const {},
  });

  /// Stable for the entity's lifetime. Reusing an id after a despawn means
  /// "the same thing came back", which is usually what a pool wants.
  final String id;

  /// Game-defined: 'bird', 'ball', 'bin'. The renderer switches on this rather
  /// than on ids, so a pool of twelve balls needs one branch.
  final String kind;

  /// Immutable per-entity data the renderer needs: a radius, a colour, a
  /// sprite name. Must be JSON-encodable — it crosses the wire.
  final Map<String, Object?> props;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    if (props.isNotEmpty) 'props': props,
  };

  static EntityDescriptor fromJson(Map<String, dynamic> j) => EntityDescriptor(
    id: j['id'] as String,
    kind: j['kind'] as String,
    props: (j['props'] as Map?)?.cast<String, Object?>() ?? const {},
  );
}

/// An entity as the host sees it right now: description plus transform.
class Entity {
  const Entity({
    required this.descriptor,
    required this.x,
    required this.y,
    this.angle = 0,
    this.vx = 0,
    this.vy = 0,
  });

  final EntityDescriptor descriptor;

  final double x;
  final double y;
  final double angle;

  /// Velocity, used to extrapolate when a packet arrives late. Supplying it is
  /// optional; supplying a wrong one is worse than supplying none.
  final double vx;
  final double vy;

  String get id => descriptor.id;
  String get kind => descriptor.kind;
  Map<String, Object?> get props => descriptor.props;
}

/// An entity at the current render instant, on the shared delayed timeline.
///
/// This is what a [GameView] draws. The transform has been interpolated between
/// the two snapshots bracketing this moment, so it is smooth locally *and*
/// identical on every phone.
class RenderEntity {
  const RenderEntity({
    required this.descriptor,
    required this.x,
    required this.y,
    required this.angle,
  });

  final EntityDescriptor descriptor;
  final double x;
  final double y;
  final double angle;

  String get id => descriptor.id;
  String get kind => descriptor.kind;
  Map<String, Object?> get props => descriptor.props;

  /// Convenience for the common case of a numeric prop with a default.
  double propDouble(String key, [double fallback = 0]) =>
      (descriptor.props[key] as num?)?.toDouble() ?? fallback;

  int propInt(String key, [int fallback = 0]) =>
      (descriptor.props[key] as num?)?.toInt() ?? fallback;
}
