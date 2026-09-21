import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/games/arena/arena_game.dart';
import 'package:multiscreen_slingshot/sdk/audio/audio_output.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/host/host_session.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/sdk/net/websocket_transport.dart';

/// Tapping a neighbour's chip on the placement screen makes *that phone* speak.
///
/// The whole value of the feature is which speaker the sound comes out of, so
/// the test is about routing rather than audio: a real host, two real phones —
/// one on loopback, one on a socket — and the question of whose output log
/// grew.
DeviceMetrics portraitPhone(String label) => DeviceMetrics(
  activePxWidth: 1080,
  activePxHeight: 2400,
  widthMm: 68.58,
  heightMm: 152.4,
  bezelMm: 3,
  devicePixelRatio: 3,
  label: label,
);

Future<void> waitFor(
  String what,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting for: $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Long enough for a message to cross a real socket and come back.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 120));

void main() {
  late HostSession host;
  late LoopbackPair loopback;
  late ClientSession phone1;
  late ClientSession phone2;
  late SilentAudioOutput ear1;
  late SilentAudioOutput ear2;

  setUp(() async {
    host = HostSession(name: 'test board', advertise: false);
    final address = await host.start();

    ear1 = SilentAudioOutput(keepLog: true);
    ear2 = SilentAudioOutput(keepLog: true);

    loopback = LoopbackPair();
    phone1 = ClientSession(
      transport: loopback.transport,
      metrics: portraitPhone('host phone'),
      audioOutput: ear1,
    );
    await phone1.connect();
    host.addLocalPeer(loopback.peer);

    phone2 = ClientSession(
      transport: WebSocketTransport(address.replace(host: '127.0.0.1')),
      metrics: portraitPhone('joined phone'),
      joinCode: host.joinCode,
      audioOutput: ear2,
    );
    await phone2.connect();

    await waitFor(
      'both phones calibrated',
      () => host.phones.length == 2 && host.phones.every((p) => p.calibrated),
    );
  });

  tearDown(() async {
    phone1.dispose();
    phone2.dispose();
    host.dispose();
    await loopback.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  /// Gets both phones to the placement screen, which is the only phase a poke
  /// means anything in.
  Future<void> reachPlacement() async {
    host.startGame(const ArenaGame());
    await waitFor(
      'both phones told where to sit',
      () => phone1.layout != null && phone2.layout != null,
    );
    ear1.clearLog();
    ear2.clearLog();
  }

  test('a poke sounds on the phone it names, and nowhere else', () async {
    await reachPlacement();

    phone1.poke(phone2.phoneId!);
    await settle();

    expect(
      ear2.log,
      hasLength(1),
      reason: 'the phone that was pointed at said nothing',
    );
    // Its own player's voice, in one of the two moods — which one is a coin
    // toss the host makes, and pinning it down would only pin down the coin.
    expect(ear2.log.single, matches(RegExp(r'play -?\d+ .*-(happy|sad)\.wav$')));
    expect(
      ear1.log,
      isEmpty,
      reason: 'the sound came out of the speaker that asked for it',
    );
  });

  test('poking the host works the same way round', () async {
    await reachPlacement();

    phone2.poke(phone1.phoneId!);
    await settle();

    expect(ear1.log, hasLength(1));
    expect(ear2.log, isEmpty);
  });

  test('a phone cannot make itself speak through the host', () async {
    // Not a rule for its own sake: a phone that wants its own noise can make
    // it locally, and a round trip that plays a sound where the finger already
    // is would be the one case the feature is not for.
    await reachPlacement();

    phone1.poke(phone1.phoneId!);
    await settle();

    expect(ear1.log, isEmpty);
    expect(ear2.log, isEmpty);
  });

  test('a poke outside the placement phase is ignored', () async {
    // The lobby has the phones in pockets, and mid-round this would be a way
    // to drop a noise into somebody else's game.
    expect(host.phase, HostPhase.lobby);
    ear1.clearLog();
    ear2.clearLog();

    phone1.poke(phone2.phoneId!);
    await settle();

    expect(ear2.log, isEmpty);
  });
}
