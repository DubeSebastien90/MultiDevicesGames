library;

class EntityDescriptor {
  const EntityDescriptor({
    required this.id,
    required this.kind,
    this.props = const {},
  });

  final String id;

  final String kind;

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

  final double vx;
  final double vy;

  String get id => descriptor.id;
  String get kind => descriptor.kind;
  Map<String, Object?> get props => descriptor.props;
}

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

  double propDouble(String key, [double fallback = 0]) =>
      (descriptor.props[key] as num?)?.toDouble() ?? fallback;

  int propInt(String key, [int fallback = 0]) =>
      (descriptor.props[key] as num?)?.toInt() ?? fallback;
}
