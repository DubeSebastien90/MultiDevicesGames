import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/net/udp_discovery.dart';

/// Discovery over real sockets.
///
/// The unit tests around [GameBeacon] only prove the wire format parses; this
/// is the one that proves a packet actually leaves one socket and arrives at
/// another. It binds a real UDP port and broadcasts on the machine's network,
/// so a firewall prompt on first run is expected.
void main() {
  _unhandledErrorTests();

  test('a broadcaster is heard by a listener, and disappears when it stops',
      () async {
    final beacon = UdpGameAdvertiser(
      id: 'live-test',
      name: 'live test board',
      address: Uri.parse('ws://127.0.0.1:8080'),
    );
    final listener = UdpGameFinder();

    await listener.start();
    await beacon.start();

    expect(
      beacon.failure,
      isNull,
      reason: 'could not broadcast: ${beacon.failure}',
    );
    expect(
      listener.failure,
      isNull,
      reason: 'could not listen: ${listener.failure}',
    );

    await _until(
      'the game to be heard',
      () => listener.games.any((g) => g.id == 'live-test'),
    );

    final heard = listener.games.firstWhere((g) => g.id == 'live-test');
    expect(heard.name, 'live test board');
    expect(heard.uri, Uri.parse('ws://127.0.0.1:8080'));
    expect(heard.open, isTrue);

    // The count is live, not baked in at start.
    beacon.update(players: 3, open: false);
    await _until(
      'the updated player count',
      () => listener.games.any((g) => g.id == 'live-test' && g.players == 3),
    );
    expect(
      listener.games.firstWhere((g) => g.id == 'live-test').open,
      isFalse,
    );

    // A game that goes away stops being listed, without anyone announcing it.
    beacon.dispose();
    await _until(
      'the stopped game to age out',
      () => listener.games.every((g) => g.id != 'live-test'),
      timeout: kBeaconTimeout + const Duration(seconds: 4),
    );

    listener.dispose();
  });

  // Leaving a lobby a moment after creating it disposes the advertiser while
  // its bind is still in flight. It used to finish starting anyway and announce
  // the abandoned game, once a second, for as long as the app ran.
  test('an advertiser disposed while starting never announces', () async {
    final listener = UdpGameFinder();
    await listener.start();

    final ghost = UdpGameAdvertiser(
      id: 'ghost-test',
      name: 'ghost',
      address: Uri.parse('ws://127.0.0.1:8080'),
    );
    final starting = ghost.start();
    ghost.dispose();
    await starting;
    expect(ghost.running, isFalse);

    // Well past the first beacon and a probe answer.
    listener.refresh();
    await Future<void>.delayed(kBeaconInterval * 2.5);
    expect(listener.games.where((g) => g.id == 'ghost-test'), isEmpty);

    listener.dispose();
  });

  // Same shape on the joining side: open the sheet, back straight out.
  test('a finder disposed while starting stays quiet and lets go', () async {
    final escaped = <Object>[];

    await runZonedGuarded(() async {
      final finder = UdpGameFinder();
      final starting = finder.start();
      finder.dispose();
      await starting;

      // Something beaconing, so a socket left open would have news to deliver
      // to the disposed notifier.
      final beacon = UdpGameAdvertiser(
        id: 'late-test',
        name: 'late',
        address: Uri.parse('ws://127.0.0.1:8080'),
      );
      await beacon.start();
      await Future<void>.delayed(kBeaconInterval * 1.5);
      beacon.dispose();
    }, (error, _) => escaped.add(error));

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(escaped, isEmpty, reason: '$escaped');
  });
}

/// A socket refusal must never escape as an unhandled error.
///
/// `RawDatagramSocket.send` does not throw at the call site when the OS refuses
/// it — sandboxed macOS returns `Operation not permitted` and Dart reports it
/// asynchronously, on the socket's own stream. A `try`/`catch` around `send`
/// cannot see that, so without an `onError` on the listen it takes down
/// whatever was awaiting: in this app, hosting a game.
void _unhandledErrorTests() {
  test('no socket error escapes the broadcaster or the listener', () async {
    final escaped = <Object>[];

    await runZonedGuarded(() async {
      final beacon = UdpGameAdvertiser(
        id: 'zone-test',
        name: 'zone test',
        address: Uri.parse('ws://127.0.0.1:8080'),
      );
      final listener = UdpGameFinder();

      await listener.start();
      await beacon.start();

      // Long enough for several beacons and any refusal to come back.
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      beacon.dispose();
      listener.dispose();
    }, (error, _) => escaped.add(error));

    // Drain anything queued behind the zone.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(
      escaped,
      isEmpty,
      reason: 'these must be reported through `failure`, never thrown: '
          '$escaped',
    );
  });
}

Future<void> _until(
  String what,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
