part of 'pitch_cars_sim.dart';

class _CarContactListener extends ContactListener {
  _CarContactListener(this.sim);
  final PitchCarsSim sim;

  @override
  void beginContact(Contact contact) {
    _crash(contact);
    final a = contact.fixtureA.body.userData;
    final b = contact.fixtureB.body.userData;
    if (a is String &&
        b is String &&
        sim._order.contains(a) &&
        sim._order.contains(b) &&
        !sim._finished.contains(a) &&
        !sim._finished.contains(b)) {
      sim._lastHitBy[a] = b;
      sim._lastHitBy[b] = a;
      sim._lastHitAt[a] = sim._sinceLaunch;
      sim._lastHitAt[b] = sim._sinceLaunch;
      sim._snapshotBeforeHit(a);
      sim._snapshotBeforeHit(b);
    }
  }

  void _crash(Contact contact) {
    final bodyA = contact.fixtureA.body;
    final bodyB = contact.fixtureB.body;
    final a = bodyA.userData;
    final b = bodyB.userData;
    if (a is! String || b is! String) return;
    final aCar = sim._order.contains(a);
    final bCar = sim._order.contains(b);
    if (!aCar && !bCar) return;

    for (final (id, isCar) in [(a, aCar), (b, bCar)]) {
      if (isCar &&
          (sim._finished.contains(id) || sim._fallenFor.containsKey(id))) {
        return;
      }
    }
    final other = aCar ? b : a;
    final isWall = other.startsWith('wall') || other.startsWith('cornerWall');
    if (!(aCar && bCar) && !isWall) return;

    final closing = (bodyA.linearVelocity - bodyB.linearVelocity).length;
    if (closing < sim.scale.restSpeed * PitchCarsConfig.crashSpeedFactor) {
      return;
    }

    final car = aCar ? bodyA : bodyB;
    final at = aCar && bCar
        ? (bodyA.position + bodyB.position) / 2
        : car.position;
    sim._crashAt(at.x, at.y);
  }

  @override
  void endContact(Contact contact) {}
  @override
  void preSolve(Contact contact, Manifold oldManifold) {}
  @override
  void postSolve(Contact contact, ContactImpulse impulse) {}
}
