part of 'pitch_cars_sim.dart';

/// Records which car last touched which, for the off-track reset rule.
class _CarContactListener extends ContactListener {
  _CarContactListener(this.sim);
  final PitchCarsSim sim;

  @override
  void beginContact(Contact contact) {
    final a = contact.fixtureA.body.userData;
    final b = contact.fixtureB.body.userData;
    if (a is String &&
        b is String &&
        sim._order.contains(a) &&
        sim._order.contains(b)) {
      sim._lastHitBy[a] = b;
      sim._lastHitBy[b] = a;
      sim._lastHitAt[a] = sim._sinceLaunch;
      sim._lastHitAt[b] = sim._sinceLaunch;
      sim._snapshotBeforeHit(a);
      sim._snapshotBeforeHit(b);
    }
  }

  @override
  void endContact(Contact contact) {}
  @override
  void preSolve(Contact contact, Manifold oldManifold) {}
  @override
  void postSolve(Contact contact, ContactImpulse impulse) {}
}
