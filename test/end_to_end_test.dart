
import 'package:flutter_test/flutter_test.dart';
import 'package:multiscreen_slingshot/sdk/model/phone_layout.dart';
import 'package:multiscreen_slingshot/games/arena/arena_game.dart';
import 'package:multiscreen_slingshot/games/dodgeball/dodgeball_game.dart';
import 'package:multiscreen_slingshot/sdk/client/client_session.dart';
import 'package:multiscreen_slingshot/sdk/host/host_session.dart';
import 'package:multiscreen_slingshot/sdk/model/device_metrics.dart';
import 'package:multiscreen_slingshot/sdk/net/loopback_transport.dart';
import 'package:multiscreen_slingshot/sdk/net/websocket_transport.dart';

/// The whole platform, wired up for real: a host running a game through the SDK
/// contract, its own loopback viewport, and a second phone on an actual
/// WebSocket.
///
/// This covers every step except the pixels — transport, the join gate, board
/// planning, the calibration handshake, entity spawn/despawn, the sim loop, the
/// scoreboard, and the interpolated playback both phones render from.
DeviceMetrics portraitPhone(String label) => DeviceMetrics(
  // The app is locked portrait, so a phone measures itself short-edge-first.
  activePxWidth: 1080,
  activePxHeight: 2400,
  widthMm: 68.58, // 400 dpi
  heightMm: 152.4,
  bezelMm: 3,
  devicePixelRatio: 3,
  label: label,
);

/// Polls [condition] until it holds, so the test follows the real async flow
/// instead of guessing at sleep durations.
Future<void> waitFor(
  String what,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for: $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late HostSession host;
  late LoopbackPair loopback;
  late ClientSession phone1; // the host's own screen
  late ClientSession phone2; // a real socket
  late Uri address;

  setUp(() async {
    // No UDP beacon here: this suite is about the game, and binding a
    // broadcast socket on a build machine is a different kind of flaky.
    // Discovery has its own test.
    host = HostSession(name: 'test board', advertise: false);
    address = await host.start();

    loopback = LoopbackPair();
    phone1 = ClientSession(
      transport: loopback.transport,
      metrics: portraitPhone('host phone'),
    );
    await phone1.connect();
    host.addLocalPeer(loopback.peer);

    // Loop back over the real stack rather than trusting the advertised LAN IP,
    // which on a build machine may not be routable to itself.
    final local = address.replace(host: '127.0.0.1');
    phone2 = ClientSession(
      transport: WebSocketTransport(local),
      metrics: portraitPhone('joined phone'),
      joinCode: host.joinCode,
    );
    await phone2.connect();
  });

  tearDown(() async {
    phone1.dispose();
    phone2.dispose();
    host.dispose();
    await loopback.dispose();
    // Let the server socket actually let go before the next test binds.
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  test('the host advertises a ws:// address a joiner can use', () {
    expect(address.scheme, 'ws');
    expect(address.port, greaterThan(0));
    expect(address.host, isNotEmpty);
  });

  test('both phones handshake, get placed, and start playing', () async {
    await waitFor('both phones calibrated', () =>
        host.phones.length == 2 && host.phones.every((p) => p.calibrated));

    expect(host.canStart, isTrue);
    expect(host.blockedReason, isNull);
    expect(host.upcoming!.manifest.id, 'flood');

    // One tap. Planning the board and building the renderer happen inside it —
    // there is no arrangement screen to pass through.
    //
    // A named game rather than Play, because the numbers below are a *row's*
    // geometry — two phones side by side, one bezel pair apart. Whichever game
    // the playlist happens to open with is not the subject here.
    host.startGame(const ArenaGame());
    expect(host.phase, HostPhase.placing);

    await waitFor(
      'both phones told where to sit',
      () => phone1.layout != null && phone2.layout != null,
    );
    expect(phone1.phase, ClientPhase.placing);
    expect(phone2.phase, ClientPhase.placing);

    // Identical phones, so the game's sort is a no-op and join order stands.
    expect(phone1.layout!.index, 0);
    expect(phone2.layout!.index, 1);
    expect(phone1.layout!.leftEdge, closeTo(0, 1e-9));
    expect(phone2.layout!.leftEdge, closeTo(15.24 + 0.6, 1e-9));
    expect(phone2.layout!.placement, contains('right of phone 1'));

    // Both were told what they are about to play, and how to stand for it.
    expect(phone1.manifest!.title, 'Arena');
    expect(phone2.instruction, contains('side by side'));

    // Both were also handed the compiled board, in board order — this is what
    // the placement diagram draws, and it must be the layout the game chose
    // rather than anything reconstructed from the lobby's join order.
    expect(phone1.slices, hasLength(2));
    expect(
      phone1.slices.map((s) => s.phoneId).toList(),
      phone2.slices.map((s) => s.phoneId).toList(),
      reason: 'every phone must be shown the same arrangement',
    );
    expect(phone1.slices.first.viewport.left, closeTo(0, 1e-9));
    expect(phone1.slices.last.viewport.left, greaterThan(0),
        reason: 'the second phone sits along the board from the first');
    expect(phone1.slices.last.viewport.left,
        closeTo(phone2.slices.last.viewport.left, 1e-9),
        reason: 'two phones disagreed about where the second screen is');
    expect(phone1.slices.first.label, isNotEmpty);

    // Nothing starts until both humans promise they are in place.
    phone1.confirmPlacement();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(host.phase, HostPhase.placing, reason: 'one confirm is not enough');

    phone2.confirmPlacement();
    await waitFor('play started', () => host.phase == HostPhase.playing);

    await waitFor(
      'both phones playing with a world to draw',
      () =>
          phone1.phase == ClientPhase.playing &&
          phone2.phase == ClientPhase.playing &&
          phone1.frameAt(16)?.entities.isNotEmpty == true &&
          phone2.frameAt(16)?.entities.isNotEmpty == true,
    );

    // Both were handed the same world description.
    final a = phone1.frameAt(16)!;
    final b = phone2.frameAt(16)!;
    expect(a.entities.keys.toSet(), b.entities.keys.toSet());
    expect(a.entities, isNotEmpty);
    expect(a.board.width, closeTo(31.08, 1e-9));

    await waitFor(
      'snapshots streaming to both',
      () => phone1.buffer.bufferedSnapshots > 3 &&
          phone2.buffer.bufferedSnapshots > 3,
    );
  });

  test('balls spawn and despawn on every phone without a hand-written message',
      () async {
    // Dodgeball spawns balls from the walls as the round runs, which is the
    // point: they appear on a phone that never heard about them at world-init.
    await waitFor('both calibrated', () =>
        host.phones.length == 2 && host.phones.every((p) => p.calibrated));
    host.startGame(const DodgeballGame());
    await waitFor('placed again', () => phone2.phase == ClientPhase.placing);
    phone1.confirmPlacement();
    phone2.confirmPlacement();
    await waitFor('dodgeball running', () => host.phase == HostPhase.playing);

    // A ball the sim spawned mid-round appears on the *joined* phone, which
    // never heard about it at world-init time.
    await waitFor(
      'a ball to reach the far phone',
      () => phone2.frameAt(16)?.ofKind('ball').isNotEmpty == true,
      timeout: const Duration(seconds: 8),
    );

    final ball = phone2.frameAt(16)!.ofKind('ball').first;
    expect(ball.propDouble('radius'), greaterThan(0),
        reason: 'the descriptor arrived with the spawn, not just a transform');
  });

  test('every phone assembles the same roster, without a new message', () async {
    await _startPlaying(host, phone1, phone2);

    // Colour has always ridden on the slices, and every phone has always
    // received them — so a roster of people, with their characters, art and
    // sounds, costs nothing on the wire. This is the assembly each game used to
    // do for itself.
    for (final phone in [phone1, phone2]) {
      expect(phone.roster.length, 2);
      expect(
        phone.roster.players.map((p) => p.phoneId).toList(),
        phone1.roster.players.map((p) => p.phoneId).toList(),
        reason: 'two phones disagreed about who is playing',
      );
    }

    // Everyone is somebody different, which is the host's promise and the
    // reason one character per colour needs no second allocator.
    final colors = phone2.roster.players.map((p) => p.color.id).toSet();
    expect(colors, hasLength(2));
    expect(
      phone2.roster.players.map((p) => p.character.name).toSet(),
      hasLength(2),
    );

    // And each phone can find itself, which is the one thing a player must
    // never get wrong.
    final me = phone2.roster.byPhone(phone2.phoneId!);
    expect(me, isNotNull);
    expect(me!.color.id, phone2.myColor?.id);
    expect(me.title, contains(me.character.name));
  });
}

/// Drives the handshake to the point where both phones are rendering.
Future<void> _startPlaying(
  HostSession host,
  ClientSession phone1,
  ClientSession phone2,
) async {
  await waitFor('both calibrated', () =>
      host.phones.length == 2 && host.phones.every((p) => p.calibrated));
  // A specific game rather than the playlist: this helper waits for entities
  // to render, and the first game a two-phone table would otherwise get draws
  // itself from shared state instead.
  host.startGame(const ArenaGame());
  await waitFor(
    'layouts delivered',
    () => phone1.layout != null && phone2.layout != null,
  );
  phone1.confirmPlacement();
  phone2.confirmPlacement();
  await waitFor(
    'playing',
    () => phone1.phase == ClientPhase.playing &&
        phone2.phase == ClientPhase.playing &&
        phone1.frameAt(16)?.entities.isNotEmpty == true,
  );
  await waitFor(
    'snapshots flowing',
    () => phone1.buffer.bufferedSnapshots > 3 &&
        phone2.buffer.bufferedSnapshots > 3,
  );
}

/// Left/top edge of a compiled screen, which is what these expectations were
/// originally written against. The layout itself is centre-based now, because a
/// screen that can be turned has no meaningful axis-aligned corner.
extension EdgeReadout on PhoneLayout {
  double get leftEdge => viewport.left;
  double get topEdge => viewport.top;
}
