import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/net/discovery.dart';

/// Discovery over real sockets.
///
/// The unit tests around [GameBeacon] only prove the wire format parses; this
/// is the one that proves a packet actually leaves one socket and arrives at
/// another. It binds a real UDP port and broadcasts on the machine's network,
/// so a firewall prompt on first run is expected.
void main() {
  test('a broadcaster is heard by a listener, and disappears when it stops',
      () async {
    final beacon = DiscoveryBroadcaster(
      id: 'live-test',
      name: 'live test board',
      address: Uri.parse('ws://127.0.0.1:8080'),
    );
    final listener = DiscoveryListener();

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
