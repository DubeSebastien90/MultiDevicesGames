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
              // The entity id is the phone id, so a car already knows whose it is;
              // this says it in the one place `ShapeView` looks.
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

  /// The road, as a single entity carrying the centerline.
  ///
  /// This used to be one box per segment — sixty to a hundred and thirty of
  /// them, depending on the table — and the union of those boxes is not the
  /// shape the physics tests. `PitchTrack.isOnTrack` asks whether a car is
  /// within half a width of the centerline *polyline*, which rounds off every
  /// bend and puts a half-disc past each end; a chain of rectangles has square
  /// outer corners and stops flat. Cars sat on tarmac that was not drawn, and
  /// `ShapeView`'s own corner rounding shaved every segment besides.
  ///
  /// So the centerline goes over the wire once and `PitchCarsView` strokes it,
  /// round-capped and round-joined, which *is* that set rather than an
  /// approximation of it. Fewer entities than before, and no way for the two
  /// to disagree: both ends read [PitchTrack.collisionOutline].
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

  /// Kerbs on the outside of every bend tight enough to throw a car off it.
  ///
  /// Which bends those are is [CornerWalls]'s business; this turns each one
  /// into something a car can hit and something a player can see.
  ///
  /// A `ChainShape` rather than a row of thin boxes, and that is not a detail.
  /// Box2D chains carry ghost vertices — each edge knows about its neighbours —
  /// which is what stops a fast car catching on the joint between two segments
  /// and being flung back across the road. A line of separate box fixtures has
  /// no such thing, and a barrier assembled from them snags. The cars are
  /// `bullet: true` besides, so a hard shot is swept against this rather than
  /// teleported through it.
  ///
  /// The body carries an id like every other, but no `addBody`: a wall never
  /// moves, so pushing its transform into the 60 Hz stream would be sixty
  /// messages a second saying the same thing. It goes out once, with the road,
  /// as a drawing.
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

  /// One entity carrying a polyline, positioned at the middle of its own
  /// bounding box with the points local to that — the convention every shape
  /// in this codebase follows, and what keeps the box the platform culls
  /// against the shape's own rather than the whole board's.
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

  /// Finish band center. On a line the band ends flush with the road's end,
  /// so the whole checkerboard sits on tarmac — centred on the end, its far
  /// half ran straight off along the last tangent, past a road that usually
  /// curves away there. On a loop it straddles 0, the start/finish point a
  /// lap measures from, where the starting grid's row 0 already sits.
  double get _finishCenter => track.closed
      ? 0.0
      : math.max(track.length - _finishBandLen / 2, _finishBandLen / 2);

  /// Where the band begins: the progress a car needs before it can finish.
  double get _finishStart => track.closed
      ? track.length - _finishBandLen / 2
      : _finishCenter - _finishBandLen / 2;

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

  /// The checkerboard, bent along the road.
  ///
  /// Each tile is a quad whose corners sit on the centerline's own normals at
  /// the tile's two column boundaries, so the band curves with the road the
  /// way the ribbon does. Neighbouring tiles share their corners exactly —
  /// no seams, no overlap — and none of it reaches past `widthWorld / 2`.
  ///
  /// On a line the pattern carries on over the round cap past the road's
  /// end — tarmac a car can stand on, so it would be odd left bare. Those
  /// extra columns run straight on along the last tangent and are clipped by
  /// the view to the cap's own disc ([PitchCarsConfig.finishClip]).
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
