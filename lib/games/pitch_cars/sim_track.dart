part of 'pitch_cars_sim.dart';

/// Building the starting grid, the track ribbon and the finish checkerboard.
extension _TrackBuilding on PitchCarsSim {
  /// Staggered two-lane grid rather than one row across the ribbon — the
  /// track is only [PitchCarsConfig.trackWidthWorld] wide, so four cars
  /// abreast would spawn overlapping and the outer two would sit hard
  /// against the edge with no room for a shot to deviate.
  Vector2 _startPositionFor(int index) {
    final reversedIndex = _order.length - 1 - index;
    final lane = reversedIndex.isEven ? -1 : 1;
    final row = reversedIndex ~/ 2;
    final arc = row * PitchCarsConfig.startRowSpacingWorld;
    final start = track.pointAtArclength(arc);
    final tangent = track.tangentAt(arc);
    final normal = Vector2(-tangent.y, tangent.x);
    final offset = lane * PitchCarsConfig.startLaneOffsetWorld;
    return Vector2(start.x + normal.x * offset, start.y + normal.y * offset);
  }

  void _placeCars() {
    for (var i = 0; i < _order.length; i++) {
      final pos = _startPositionFor(i);
      addBody(
        _order[i],
        'car',
        BodyDef(
          type: BodyType.dynamic,
          position: pos,
          linearDamping: PitchCarsConfig.carLinearDamping,
          angularDamping: PitchCarsConfig.carAngularDamping,
          bullet: true,
        ),
        props: {
          ShapeProps.shape: ShapeKind.circle,
          ShapeProps.radius: PitchCarsConfig.carVisualRadius,
          ShapeProps.color:
              PitchCarsConfig.carColors[i % PitchCarsConfig.carColors.length],
          ShapeProps.spin: true,
        },
      ).createFixture(
        FixtureDef(
          CircleShape(radius: PitchCarsConfig.carRadius),
          density: PitchCarsConfig.carDensity,
          friction: PitchCarsConfig.carFriction,
          restitution: PitchCarsConfig.carRestitution,
        ),
      );
    }
  }

  void _buildTrackEntities() {
    final pts = track.closed
        ? [...track.waypoints, track.waypoints.first]
        : track.waypoints;
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final segLen = math.sqrt(dx * dx + dy * dy);
      if (segLen < 1e-6) continue;
      _trackEntities.add(
        Entity(
          descriptor: EntityDescriptor(
            id: 'trackSeg$i',
            kind: 'trackSegment',
            props: {
              ShapeProps.shape: ShapeKind.box,
              ShapeProps.width: segLen,
              ShapeProps.height: track.widthWorld,
              ShapeProps.color: PitchCarsConfig.colorTrack,
            },
          ),
          x: (a.x + b.x) / 2,
          y: (a.y + b.y) / 2,
          angle: math.atan2(dy, dx),
        ),
      );
    }
  }

  /// Finish band center: arclength [track.length] on a line (the road's
  /// actual end), or 0 on a loop (the start/finish point a lap measures
  /// from, where the starting grid's row 0 already sits).
  double get _finishCenter => track.closed ? 0.0 : track.length;

  double get _finishBandLen =>
      PitchCarsConfig.finishLineCols *
      (track.widthWorld / PitchCarsConfig.finishLineRows);

  /// Whether arclength [s] falls inside the finish band, wrapping around
  /// for a closed track since the band there straddles arclength 0.
  bool _inFinishZone(double s) {
    var delta = (s - _finishCenter).abs();
    if (track.closed) delta = math.min(delta, track.length - delta);
    return delta <= _finishBandLen / 2;
  }

  void _buildFinishLineEntities() {
    final center = _finishCenter;
    final rows = PitchCarsConfig.finishLineRows;
    final cols = PitchCarsConfig.finishLineCols;
    final tileSize = track.widthWorld / rows;
    final bandLen = _finishBandLen;

    final base = track.pointAtArclength(center);
    final tangent = track.tangentAt(center);
    final normal = Waypoint(-tangent.y, tangent.x);
    final angle = math.atan2(tangent.y, tangent.x);

    for (var col = 0; col < cols; col++) {
      final along = (col + 0.5) * tileSize - bandLen / 2;
      for (var row = 0; row < rows; row++) {
        final lateral = (row + 0.5) * tileSize - track.widthWorld / 2;
        final color = (row + col) % 2 == 0
            ? PitchCarsConfig.finishLineColorA
            : PitchCarsConfig.finishLineColorB;
        _trackEntities.add(
          Entity(
            descriptor: EntityDescriptor(
              id: 'finishTile${row}_$col',
              kind: 'finishLine',
              props: {
                ShapeProps.shape: ShapeKind.box,
                ShapeProps.width: tileSize,
                ShapeProps.height: tileSize,
                ShapeProps.color: color,
              },
            ),
            x: base.x + tangent.x * along + normal.x * lateral,
            y: base.y + tangent.y * along + normal.y * lateral,
            angle: angle,
          ),
        );
      }
    }
  }
}
