part of 'pitch_cars_sim.dart';

extension _TrackBuilding on PitchCarsSim {
  Vector2 _startPositionFor(int index) {
    final reversedIndex = _order.length - 1 - index;
    final lane = reversedIndex.isEven ? -1 : 1;
    final row = reversedIndex ~/ 2;
    final arc = row * scale.startRowSpacingWorld;
    final start = track.pointAtArclength(arc);
    final tangent = track.tangentAt(arc);
    final normal = Vector2(-tangent.y, tangent.x);
    final offset = lane * scale.startLaneOffsetWorld;
    return Vector2(start.x + normal.x * offset, start.y + normal.y * offset);
  }

  void _placeCars() {
    for (var i = 0; i < _order.length; i++) {
      final pos = _startPositionFor(i);
      _fixtureOf[_order[i]] =
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
              ShapeProps.radius: scale.carVisualRadius,
              ShapeProps.color: _colorOf[_order[i]]!.value.toARGB32(),
              ShapeProps.spin: true,
              ShapeProps.player: _order[i],
            },
          ).createFixture(
            FixtureDef(
              CircleShape(radius: scale.carRadius),
              density: PitchCarsConfig.carDensity,
              friction: PitchCarsConfig.carFriction,
              restitution: PitchCarsConfig.carRestitution,
            ),
          );
    }
  }

  void _buildTrackEntities() {
    final pts = track.collisionOutline;
    if (pts.length < 2) return;

    _trackEntities.add(
      _polylineEntity(
        id: 'trackRibbon',
        kind: PitchCarsConfig.ribbonKind,
        points: pts,
        thickness: track.widthWorld,
        color: PitchCarsConfig.colorTrack,
      ),
    );
  }

  void _buildCornerWalls() {
    final walls = CornerWalls.of(track);

    for (var i = 0; i < walls.length; i++) {
      final points = walls[i].points;

      final body = world.createBody(BodyDef(position: Vector2.zero()))
        ..userData = 'cornerWall$i';
      body.createFixture(
        FixtureDef(
          ChainShape()
            ..createChain([for (final p in points) Vector2(p.x, p.y)]),
          friction: PitchCarsConfig.wallFriction,
          restitution: PitchCarsConfig.wallRestitution,
        ),
      );

      _trackEntities.add(
        _polylineEntity(
          id: 'cornerWall$i',
          kind: PitchCarsConfig.wallKind,
          points: points,
          thickness: track.widthWorld * PitchCarsConfig.wallThicknessFraction,
          color: PitchCarsConfig.colorWall,
        ),
      );
    }
  }

  Entity _polylineEntity({
    required String id,
    required String kind,
    required List<Waypoint> points,
    required double thickness,
    required int color,
    Map<String, Object?> extra = const {},
  }) {
    var minX = points.first.x, maxX = points.first.x;
    var minY = points.first.y, maxY = points.first.y;
    for (final p in points) {
      minX = math.min(minX, p.x);
      maxX = math.max(maxX, p.x);
      minY = math.min(minY, p.y);
      maxY = math.max(maxY, p.y);
    }
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;

    return Entity(
      descriptor: EntityDescriptor(
        id: id,
        kind: kind,
        props: {
          PitchCarsConfig.ribbonPoints: [
            for (final p in points) ...[p.x - cx, p.y - cy],
          ],
          PitchCarsConfig.ribbonWidth: thickness,
          PitchCarsConfig.ribbonColor: color,
          ...extra,
        },
      ),
      x: cx,
      y: cy,
    );
  }

  double get _finishCenter => track.closed
      ? 0.0
      : math.max(track.length - _finishBandLen / 2, _finishBandLen / 2);

  double get _finishStart => track.closed
      ? track.length - _finishBandLen / 2
      : _finishCenter - _finishBandLen / 2;

  double get _finishBandLen =>
      PitchCarsConfig.finishLineCols *
      (track.widthWorld / PitchCarsConfig.finishLineRows);

  bool _inFinishZone(double s) {
    if (!track.closed) return s >= _finishStart - 1e-6;
    var delta = (s - _finishCenter).abs();
    if (track.closed) delta = math.min(delta, track.length - delta);
    return delta <= _finishBandLen / 2;
  }

  void _buildFinishLineEntities() {
    final rows = PitchCarsConfig.finishLineRows;
    final tileSize = track.widthWorld / rows;
    final bandStart = _finishCenter - _finishBandLen / 2;
    final roadCols = PitchCarsConfig.finishLineCols;
    final capCols = track.closed
        ? 0
        : ((track.widthWorld / 2) / tileSize - 1e-9).ceil();
    final end = track.pointAtArclength(track.length);
    final endTangent = track.tangentAt(track.length);

    Waypoint corner(int col, int row) {
      final s = bandStart + col * tileSize;
      final past = track.closed ? 0.0 : math.max(0.0, s - track.length);
      final p = track.pointAtArclength(s);
      final t = past > 0 ? endTangent : track.tangentAt(s);
      final lateral = row * tileSize - track.widthWorld / 2;
      return Waypoint(
        p.x + t.x * past - t.y * lateral,
        p.y + t.y * past + t.x * lateral,
      );
    }

    for (var col = 0; col < roadCols + capCols; col++) {
      final onCap = col >= roadCols;
      for (var row = 0; row < rows; row++) {
        final color = (row + col) % 2 == 0
            ? PitchCarsConfig.finishLineColorA
            : PitchCarsConfig.finishLineColorB;
        final points = [
          corner(col, row),
          corner(col + 1, row),
          corner(col + 1, row + 1),
          corner(col, row + 1),
        ];
        final tile = _polylineEntity(
          id: 'finishTile${row}_$col',
          kind: PitchCarsConfig.finishTileKind,
          points: points,
          thickness: 0,
          color: color,
          extra: onCap
              ? {
                  PitchCarsConfig.finishClip: [
                    end.x,
                    end.y,
                    track.widthWorld / 2,
                  ],
                }
              : const {},
        );
        _trackEntities.add(tile);
      }
    }
  }
}
